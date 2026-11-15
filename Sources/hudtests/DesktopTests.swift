import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import VideoToolbox
import HudCore

// The desktop stream, end to end without a network: frames are encoded as HudCast encodes them,
// packed as the wire carries them, split into arbitrary pieces as TCP delivers them, and turned
// back into sample buffers as the phone does. If VideoToolbox can decode those, so can the
// phone's display layer.

func runDesktopTests() {
    print("\nDesktop stream")

    test("wire: messages survive being split at every possible byte") {
        let a = DesktopWire.pack(.windows, Data("[1,2,3]".utf8))
        let b = DesktopWire.pack(.frame, Data(repeating: 7, count: 300))
        let stream = a + b
        for cut in 1..<stream.count {
            var parser = DesktopWire.Parser()
            let first = parser.feed(stream.prefix(cut))
            let rest = parser.feed(stream.suffix(from: cut))
            let all = first + rest
            guard all.count == 2 else { return expect(false, "cut \(cut): \(all.count) messages") }
            expectEqual(all[0].0, .windows)
            expectEqual(all[1].1.count, 300)
        }
    }

    test("layout: browser and desktop split the space right of the column in halves") {
        let layout = GlassesLayout(visible: [.browser, .desktop, .clock])
        let browser = layout.browserFrame!, desktop = layout.desktopFrame!, area = layout.mainArea!
        expectEqual(browser.width, desktop.width)
        expectEqual(browser.minX, area.minX)
        expectEqual(desktop.maxX, area.maxX)
        expectEqual(desktop.minX - browser.maxX, GlassesLayout.gap)
        expect(!browser.intersects(desktop), "panels overlap")
    }

    test("layout: the desktop alone takes the canvas inside the safe inset") {
        let layout = GlassesLayout(visible: [.desktop])
        let inset = HudTheme.safeInset
        expectEqual(layout.desktopFrame,
                    CGRect(x: inset, y: inset, width: 1920 - inset * 2, height: 1080 - inset * 2))
        expect(layout.browserFrame == nil, "no browser")
    }

    test("layout: a click on the picture is a fraction of it, and the letterbox is nothing") {
        let layout = GlassesLayout(visible: [.browser, .desktop], desktopAspect: 16 / 10)
        let picture = layout.desktopPicture!
        expectEqual((picture.width / picture.height * 100).rounded(), 160)
        let hit = layout.hitTest(CGPoint(x: picture.minX + picture.width / 4,
                                         y: picture.minY + picture.height * 0.75))
        guard case let .desktop(p) = hit else { return expect(false, "\(hit)") }
        expect(abs(p.x - 0.25) < 0.001 && abs(p.y - 0.75) < 0.001, "\(p)")
        // Above the picture, inside the panel: the bars around a fitted picture take no clicks.
        let frame = layout.desktopFrame!
        if picture.minY > frame.minY + 2 {
            expectEqual(layout.hitTest(CGPoint(x: frame.midX, y: frame.minY + 1)), .none)
        }
        // The browser half still gets its own clicks.
        if case .page = layout.hitTest(CGPoint(x: layout.browserFrame!.midX, y: 700)) {} else {
            expect(false, "browser half lost its page")
        }
    }

    test("layout: a fullscreen video hides the desktop") {
        let layout = GlassesLayout(visible: [.browser, .desktop], fullscreen: true)
        expect(layout.desktopFrame == nil, "desktop still there")
        expectEqual(layout.browserFrame, CGRect(origin: .zero, size: HudTheme.glassesSize))
    }

    test("snapshot: the active window is found by id; unknown ids are the whole screen") {
        var desktop = HudSnapshot.Desktop.preview
        expect(desktop.activeWindow == nil, "full screen")
        desktop.source?.window = 12
        expectEqual(desktop.activeWindow, 1)
        desktop.source?.window = 99
        expect(desktop.activeWindow == nil, "unknown window")
        expectEqual((desktop.aspect * 10).rounded(), 16)
    }

    test("wire: commands round-trip as JSON") {
        let commands: [DesktopCommand] = [.move(x: 0.25, y: 0.75),
                                          .click(x: 0.5, y: 0.5, button: 1),
                                          .scroll(x: 0, y: 0, dx: 0, dy: -40),
                                          .text("olá"), .key("return"), .select(window: 42),
                                          .select(window: nil)]
        for command in commands {
            let data = try! JSONEncoder().encode(command)
            expectEqual(try? JSONDecoder().decode(DesktopCommand.self, from: data), command)
        }
    }

    test("video: encoded frames decode on the far side at the same size") {
        let width = 640, height = 400
        var packets = Data()
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var frames = 0
        guard let encoder = DesktopEncoder(width: width, height: height, output: {
            keyframe, avcc, sps, pps in
            if let sps, let pps {
                packets.append(DesktopWire.pack(.format, DesktopWire.formatPayload(sps: sps, pps: pps)))
            }
            packets.append(DesktopWire.pack(.frame, DesktopWire.framePayload(keyframe: keyframe,
                                                                             avcc: avcc)))
            frames += 1
            if frames == 6 { done.signal() }
        }) else { return expect(false, "no encoder") }

        for index in 0..<6 {
            encoder.encode(testFrame(width, height, shade: UInt8(40 * index)),
                           time: CMTime(value: CMTimeValue(index), timescale: 30))
        }
        encoder.flush()
        _ = done.wait(timeout: .now() + 5)

        var parser = DesktopWire.Parser()
        var depacketizer = DesktopDepacketizer()
        var decoded = 0
        var firstKeyframe: Bool?
        var decoder: Decoder?
        for (kind, payload) in parser.feed(packets) {
            switch kind {
            case .format:
                guard let sets = DesktopWire.parseFormat(payload) else { return expect(false, "format") }
                depacketizer.setFormat(sps: sets.sps, pps: sets.pps)
            case .frame:
                guard let frame = DesktopWire.parseFrame(payload),
                      let sample = depacketizer.sampleBuffer(avcc: frame.avcc) else {
                    return expect(false, "frame")
                }
                if firstKeyframe == nil { firstKeyframe = frame.keyframe }
                if decoder == nil { decoder = Decoder(format: depacketizer.format!) }
                if decoder?.decode(sample) == CGSize(width: width, height: height) {
                    decoded += 1
                }
            default: break
            }
        }
        expectEqual(firstKeyframe, true)
        expectEqual(decoded, 6)
        expectEqual(depacketizer.dimensions?.width, Int32(width))
    }
}

private func testFrame(_ width: Int, _ height: Int, shade: UInt8) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
    CVPixelBufferLockBaseAddress(buffer!, [])
    let base = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer!)
    for y in 0..<height {
        for x in 0..<width {
            let p = base + y * stride + x * 4
            p[0] = UInt8(x % 256); p[1] = shade; p[2] = UInt8(y % 256); p[3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer!, [])
    return buffer!
}

/// One VideoToolbox session for the whole stream, as the phone's display layer has: frames
/// after a keyframe only decode against the frames before them.
private final class Decoder {
    let session: VTDecompressionSession

    init?(format: CMVideoFormatDescription) {
        var session: VTDecompressionSession?
        guard VTDecompressionSessionCreate(allocator: nil, formatDescription: format,
                                           decoderSpecification: nil, imageBufferAttributes: nil,
                                           outputCallback: nil,
                                           decompressionSessionOut: &session) == noErr,
              let session else { return nil }
        self.session = session
    }

    deinit { VTDecompressionSessionInvalidate(session) }

    func decode(_ sample: CMSampleBuffer) -> CGSize? {
        var size: CGSize?
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [],
                                          infoFlagsOut: nil) { status, _, image, _, _ in
            if status == noErr, let image {
                size = CGSize(width: CVPixelBufferGetWidth(image),
                              height: CVPixelBufferGetHeight(image))
            }
        }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        return size
    }
}
