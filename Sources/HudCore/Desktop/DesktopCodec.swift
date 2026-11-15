import Foundation
import CoreMedia
import VideoToolbox

/// H.264 for the desktop stream: tuned for a live screen, not a film. No reordered frames, so
/// every frame can be shown the moment it arrives; a keyframe every two seconds, so a dropped
/// connection or a newly joined phone has a picture again quickly.
public final class DesktopEncoder: @unchecked Sendable {
    public typealias Output = (_ keyframe: Bool, _ avcc: Data, _ sps: Data?, _ pps: Data?) -> Void

    private var session: VTCompressionSession?
    private let output: Output
    public let width: Int
    public let height: Int
    private var forceKeyframe = true

    public init?(width: Int, height: Int, bitrate: Int = 10_000_000, fps: Int = 30,
                 output: @escaping Output) {
        self.width = width
        self.height = height
        self.output = output
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard status == noErr, let session else { return nil }
        self.session = session
        let set = { (key: CFString, value: CFTypeRef) in
            VTSessionSetProperty(session, key: key, value: value)
        }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, (fps * 2) as CFNumber)
        set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        // Text on a screen is all edges; a bitrate cap that is too tight smears it first.
        set(kVTCompressionPropertyKey_DataRateLimits,
            [bitrate * 2 / 8, 1] as CFArray)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit {
        if let session { VTCompressionSessionInvalidate(session) }
    }

    /// The next frame will be a keyframe: a phone has just connected.
    public func requestKeyframe() { forceKeyframe = true }

    public func encode(_ pixelBuffer: CVPixelBuffer, time: CMTime) {
        guard let session else { return }
        var options: CFDictionary?
        if forceKeyframe {
            forceKeyframe = false
            options = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
        }
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer,
                                        presentationTimeStamp: time, duration: .invalid,
                                        frameProperties: options, infoFlagsOut: nil) {
            [weak self] status, _, sample in
            guard status == noErr, let sample, let self else { return }
            self.emit(sample)
        }
    }

    public func flush() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    private func emit(_ sample: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            as? [[CFString: Any]]
        let keyframe = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)

        var sps: Data?, pps: Data?
        if keyframe, let format = CMSampleBufferGetFormatDescription(sample) {
            sps = Self.parameterSet(format, 0)
            pps = Self.parameterSet(format, 1)
        }

        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length,
                                          dataPointerOut: &pointer) == noErr,
              let pointer else { return }
        output(keyframe, Data(bytes: pointer, count: length), sps, pps)
    }

    private static func parameterSet(_ format: CMFormatDescription, _ index: Int) -> Data? {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size, parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil) == noErr, let pointer else { return nil }
        return Data(bytes: pointer, count: size)
    }
}

/// Turns what arrives from the Mac back into sample buffers a display layer can show.
public struct DesktopDepacketizer: Sendable {
    public private(set) var format: CMVideoFormatDescription?

    public init() {}

    public var dimensions: CMVideoDimensions? {
        format.map(CMVideoFormatDescriptionGetDimensions)
    }

    public mutating func setFormat(sps: Data, pps: Data) {
        var description: CMFormatDescription?
        sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let pointers = [spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                                ppsBytes.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sps.count, pps.count]
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description)
            }
        }
        if let description { format = description }
    }

    /// A sample buffer for one frame, marked to be shown as soon as it is decoded: there is no
    /// clock to schedule against, only "now".
    public func sampleBuffer(avcc: Data) -> CMSampleBuffer? {
        guard let format, !avcc.isEmpty else { return nil }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: avcc.count, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = avcc.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copied == noErr else { return nil }

        var sample: CMSampleBuffer?
        var size = avcc.count
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0),
                                           to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
