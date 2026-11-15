import Foundation
import ScreenCaptureKit
import CoreMedia
import HudCore

/// The screen, or one window, as a stream of encoded frames.
///
/// Captured at no more than 1920 wide, which is what the glasses can show, and without the
/// Mac's own pointer: the glasses draw theirs, at the same place, and two would be one too many.
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onSource: ((DesktopSource) -> Void)?
    /// The network is behind: skip this frame.
    var isBusy: () -> Bool = { false }

    private let output: DesktopEncoder.Output
    private let queue = DispatchQueue(label: "hudcast.capture")
    private var stream: SCStream?
    private var encoder: DesktopEncoder?
    private var lastFrame: CVPixelBuffer?
    private var frameCount: Int64 = 0

    init(output: @escaping DesktopEncoder.Output) {
        self.output = output
    }

    /// What can be streamed on its own: ordinary app windows, front to back.
    func windows() async -> [DesktopWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true) else { return [] }
        let own = Bundle.main.bundleIdentifier
        return content.windows
            .filter { window in
                window.windowLayer == 0 && window.frame.width > 120 && window.frame.height > 80
                    && window.owningApplication != nil
                    && window.owningApplication?.bundleIdentifier != own
            }
            .map { window in
                DesktopWindow(id: window.windowID,
                              app: window.owningApplication?.applicationName ?? "",
                              title: window.title ?? "")
            }
    }

    /// Starts streaming the whole main display, or one window. Replaces whatever was streaming.
    func start(window windowID: UInt32?) async {
        await stop()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            let filter: SCContentFilter
            if let windowID, let window = content.windows.first(where: { $0.windowID == windowID }) {
                filter = SCContentFilter(desktopIndependentWindow: window)
            } else {
                let main = CGMainDisplayID()
                guard let display = content.displays.first(where: { $0.displayID == main })
                        ?? content.displays.first else { return }
                filter = SCContentFilter(display: display, excludingApplications: [],
                                         exceptingWindows: [])
            }

            let rect = filter.contentRect
            let scale = CGFloat(filter.pointPixelScale)
            let (width, height) = Self.fit(width: rect.width * scale, height: rect.height * scale)
            let configuration = SCStreamConfiguration()
            configuration.width = width
            configuration.height = height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            configuration.showsCursor = false
            configuration.queueDepth = 5
            configuration.scalesToFit = true

            let encoder = DesktopEncoder(width: width, height: height, output: output)
            queue.sync {
                self.encoder = encoder
                self.lastFrame = nil
            }

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            onSource?(DesktopSource(window: windowID, width: width, height: height,
                                    host: Host.current().localizedName ?? "Mac"))
        } catch {
            NSLog("HudCast: capture failed: \(error)")
        }
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
    }

    /// Fits the source inside 1920x1200, keeping its shape. Even sizes: H.264 works in pairs.
    static func fit(width: CGFloat, height: CGFloat) -> (Int, Int) {
        let scale = min(1, 1920 / max(width, 1), 1200 / max(height, 1))
        let even = { (value: CGFloat) in max(2, Int(value * scale) / 2 * 2) }
        return (even(width), even(height))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        lastFrame = pixels
        guard !isBusy() else { return }
        frameCount += 1
        encoder?.encode(pixels, time: CMTime(value: frameCount, timescale: 30))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("HudCast: stream stopped: \(error)")
    }
}
