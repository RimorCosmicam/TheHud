import UIKit
import SwiftUI
import CoreMedia
import VideoToolbox
import HudCore

/// Host mode: this phone's glasses, drawn in a window behind the phone's own screen, filmed up to
/// thirty times a second and sent as H.264 (the same encoder and framing HudCast uses for the
/// Mac) to the Android phone, which only shows them on its glasses.
@MainActor
final class HostStreamer: NSObject {
    private static let width = 1920
    private static let height = 1080
    /// Bytes handed to the network and not yet sent: past this, frames wait for a keyframe.
    private static let backlog = 2_000_000

    private let link: RemoteLink
    private var window: UIWindow?
    private var displayLink: CADisplayLink?
    private var encoder: DesktopEncoder?
    private var pool: CVPixelBufferPool?
    /// Frames are being dropped until the next keyframe, which every later frame needs.
    private var skipping = false
    /// What a film of the glasses cannot hold (video layers draw nothing into it): where the
    /// YouTube video and the cursor are, for the Android phone to play and draw there itself,
    /// and the Mac's picture's frame, to paint in here.
    var overlay: () -> (json: [String: Any], mac: CGRect?) = { ([:], nil) }
    /// The Mac's newest frame, decoded.
    var macPicture: () -> CVPixelBuffer? = { nil }
    private var lastOverlay = Data()
    private var lastOverlayAt = Date.distantPast

    init(link: RemoteLink) {
        self.link = link
    }

    func start(in scene: UIWindowScene) {
        guard window == nil else { return }
        let window = UIWindow(windowScene: scene)
        // Half the canvas in points, drawn at twice the scale: 1920 by 1080 pixels. Below the
        // phone's own window, so it is never seen on the phone.
        window.frame = CGRect(x: 0, y: 0, width: Self.width / 2, height: Self.height / 2)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1)
        window.isUserInteractionEnabled = false
        window.rootViewController = UIHostingController(rootView: GlassesHost(liveGlass: false))
        window.isHidden = false
        self.window = window

        encoder = DesktopEncoder(width: Self.width, height: Self.height, bitrate: 8_000_000, fps: 30) {
            [weak self] keyframe, avcc, sps, pps in
            var packets = Data()
            if let sps, let pps {
                packets.append(DesktopWire.pack(.format, DesktopWire.formatPayload(sps: sps, pps: pps)))
            }
            packets.append(DesktopWire.pack(.frame, DesktopWire.framePayload(keyframe: keyframe, avcc: avcc)))
            Task { @MainActor in self?.deliver(packets, keyframe: keyframe) }
        }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Self.width,
            kCVPixelBufferHeightKey: Self.height,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)

        let displayLink = CADisplayLink(target: self, selector: #selector(film))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        encoder?.flush()
        encoder = nil
        pool = nil
        window?.isHidden = true
        window = nil
        skipping = false
    }

    /// The Android phone has a new surface to draw on, or lost its place.
    func requestKeyframe() {
        encoder?.requestKeyframe()
    }

    @objc private func film() {
        guard let window, let encoder, let pool else { return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: Self.width, height: Self.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        // UIKit draws top down, at twice the window's points.
        context.translateBy(x: 0, y: CGFloat(Self.height))
        context.scaleBy(x: 2, y: -2)
        UIGraphicsPushContext(context)
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        let (json, mac) = overlay()
        if let mac, let picture = macPicture() {
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(picture, options: nil, imageOut: &image)
            // The canvas's points are twice the window's.
            if let image {
                UIImage(cgImage: image).draw(in: CGRect(x: mac.minX / 2, y: mac.minY / 2,
                                                        width: mac.width / 2, height: mac.height / 2))
            }
        }
        UIGraphicsPopContext()
        sendOverlay(json)
        encoder.encode(buffer, time: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600))
    }

    /// When it changes, and once a second anyway: the video's time keeps the two players together.
    private func sendOverlay(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { return }
        guard data != lastOverlay || Date().timeIntervalSince(lastOverlayAt) > 1 else { return }
        lastOverlay = data
        lastOverlayAt = Date()
        link.sendPacket(DesktopWire.pack(.overlay, data))
    }

    /// To the Android phone, unless the network is behind: then nothing until a keyframe, so the
    /// picture never smears from a missing frame and the delay never grows.
    private func deliver(_ packets: Data, keyframe: Bool) {
        if skipping && !keyframe { return }
        if link.unsentBytes > Self.backlog {
            skipping = true
            encoder?.requestKeyframe()
            return
        }
        skipping = false
        link.sendPacket(packets)
    }
}
