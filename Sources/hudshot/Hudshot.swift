import Foundation
import SwiftUI
import HudCore
import simd
import CoreLocation
import WebKit
import AppKit

// hudshot — renders HudCore surfaces to PNG on a Mac, with no device and no simulator.
//
// The point is to see a change before spending a build on it. The halftone goes through the same
// Metal renderer the app uses and the chrome through the same SwiftUI views, so these images are
// the app's output at a different size rather than an illustration of it.

@main
struct Hudshot {
    @MainActor
    static func main() {
        do { try run() } catch {
            FileHandle.standardError.write("hudshot: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    @MainActor
    static func run() throws {
        let outDir = parseOutDir()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // --live fetches real weather and a real map. Off by default so CI stays deterministic
        // and the tool works with no network.
        let live = CommandLine.arguments.contains("--live")

        let renderer = try HalftoneRenderer()
        print("device: \(renderer.device.name)")
        HudTheme.bootstrap()

        // The surface occupies exactly half the display, so that is the size the shader is asked
        // for — aspect correction and dot pitch both follow the surface, not the screen.
        let scale = PhoneMetrics.scale
        let surfaceW = Int((PhoneMetrics.size.width - PhoneMetrics.surfaceMargin * 2) * scale)
        let surfaceH = Int(PhoneMetrics.trackpad * scale)
        let surfaceSize = SIMD2<Float>(Float(surfaceW), Float(surfaceH))

        let plain = try renderer.render(width: surfaceW, height: surfaceH)

        // One contact held, one 0.4s into its fade, so a still shows the touchWarp ripple.
        let touched = try renderer.render(
            width: surfaceW, height: surfaceH,
            touches: [
                .fromPixels(SIMD2(760, 520), size: surfaceSize, age: 0.0, active: 1.0),
                .fromPixels(SIMD2(420, 900), size: surfaceSize, age: 0.4, active: 0.0),
            ])

        try write(PhoneScreen(surface: plain),
                  to: outDir, "phone-idle", scale: scale)

        try write(PhoneScreen(surface: plain, keyboardUp: true),
                  to: outDir, "phone-keyboard", scale: scale)

        try write(PhoneScreen(surface: plain, keyboardUp: true, predictiveBar: true),
                  to: outDir, "phone-keyboard-predictive", scale: scale)

        try write(PhoneScreen(surface: touched, railActive: true, cornerPressed: true),
                  to: outDir, "phone-active", scale: scale)

        // The glasses canvas: 1080p, the mode the Air reports over DisplayPort. Rendered at
        // scale 1, because 1920x1080 is what the glasses are actually handed.
        try write(GlassesScreen(), to: outDir, "glasses-browser", scale: 1)

        // End to end: a real swipe through the real recogniser, driving the real cursor. If the
        // pointer in this image is not where the swipe should have put it, the engine is wrong.
        let driven = HudSnapshot(cursor: cursorAfterSwipe())
        try write(GlassesScreen(snapshot: driven),
                  to: outDir, "glasses-pointer", scale: 1)

        // The cursor on the bar: the buttons are up, and the page has scrolled under the glass.
        let bar = GlassesLayout().barFrame!
        let hovering = HudSnapshot(cursor: CGPoint(x: bar.midX + 180, y: bar.midY))
        try write(GlassesScreen(snapshot: hovering,
                                browserContent: AnyView(PageStandIn(scrolled: 150))),
                  to: outDir, "glasses-hover", scale: 1)

        // The start page, drawn by WebKit from the same HTML the phone serves.
        var editing = HudSnapshot(cursor: nil)
        editing.browser.isEditingAddress = true
        editing.browser.url = "xreal air 2 ul"
        try write(GlassesScreen(snapshot: editing), to: outDir, "glasses-address", scale: 1)

        if let home = renderHomePage() {
            var snapshot = HudSnapshot(cursor: nil)
            snapshot.browser = HudSnapshot.Browser(url: "", title: "Favorites", tabs: [],
                                                   activeTab: 0, canGoBack: false, isHome: true)
            try write(GlassesScreen(snapshot: snapshot,
                                    browserContent: AnyView(Image(decorative: home, scale: 1).resizable())),
                      to: outDir, "glasses-home", scale: 1)
        }

        if live {
            let (snapshot, ground) = try liveSnapshot()
            try write(GlassesScreen(snapshot: snapshot, mapGround: ground),
                      to: outDir, "glasses-live", scale: 1)
        }
        try write(GlassesScreen(snapshot: HudSnapshot(cursor: nil),
                                visible: [.clock, .weather, .map]),
                  to: outDir, "glasses-glance", scale: 1)

        print("\nimages in \(outDir.path)")
    }

    @MainActor
    private static func write<V: View>(_ view: V, to dir: URL, _ name: String,
                                       scale: CGFloat) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let image = renderer.cgImage else {
            throw Failure("ImageRenderer produced nothing for \(name)")
        }
        try image.writePNG(to: dir.appendingPathComponent("\(name).png"))
        report(name, dir, image.width, image.height)
    }

    private static func report(_ name: String, _ dir: URL, _ w: Int, _ h: Int) {
        let path = dir.appendingPathComponent("\(name).png").path
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        print("wrote \(name).png  \(w)x\(h)  \(bytes / 1024) KB")
    }

    /// Real weather and a real map, for a fixed coordinate.
    ///
    /// The coordinate is hard-coded rather than read from CoreLocation: a command line tool has
    /// no reasonable way to ask for location permission, and sending a real location to a third
    /// party to make a preview would be a poor trade.
    @MainActor
    private static func liveSnapshot() throws -> (HudSnapshot, Image?) {
        let lisbon = CLLocationCoordinate2D(latitude: 38.7139, longitude: -9.1334)
        var snapshot = HudSnapshot(cursor: nil)

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var weather: HudSnapshot.Weather?
        nonisolated(unsafe) var ground: CGImage?
        nonisolated(unsafe) var failure: Error?

        Task.detached {
            do {
                weather = try await OpenMeteoWeatherProvider()
                    .weather(at: lisbon, placeName: "Lisbon")
                ground = try await MapSnapshotProvider()
                    .snapshot(centre: lisbon, spanMetres: 600,
                              size: CGSize(width: 470, height: 492))
            } catch {
                failure = error
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            print("live: timed out")
            return (snapshot, nil)
        }
        if let failure {
            print("live: \(failure)")
            return (snapshot, nil)
        }

        if let weather {
            snapshot.weather = weather
            print("live weather: \(weather.temperature)\u{00B0} \(weather.condition)")
        }
        print("live map: \(ground.map { "\($0.width)x\($0.height)" } ?? "none")")
        return (snapshot, ground.map { Image(decorative: $0, scale: 2) })
    }

    /// The start page through a real WebKit, at the size the browser panel gives it. Favicons
    /// come from the network, so offline they fall back to their letters, as they would on the
    /// phone.
    @MainActor
    private static func renderHomePage() -> CGImage? {
        _ = NSApplication.shared
        let size = GlassesLayout().contentFrame!.size
        let webView = WKWebView(frame: CGRect(origin: .zero, size: size))
        webView.setValue(false, forKey: "drawsBackground")
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(HomePage.html(Favorite.defaults), baseURL: nil)

        let deadline = Date().addingTimeInterval(15)
        while !delegate.finished, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        // Let the favicons that are coming arrive.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        var result: CGImage?
        var done = false
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: size)
        configuration.snapshotWidth = NSNumber(value: Double(size.width))
        webView.takeSnapshot(with: configuration) { image, _ in
            result = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            done = true
        }
        while !done, Date() < deadline.addingTimeInterval(5) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        print(result == nil ? "home: WebKit snapshot failed" : "home: rendered by WebKit")
        return result
    }

    final class LoadWaiter: NSObject, WKNavigationDelegate {
        var finished = false
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finished = true
        }
    }

    /// Drives the engine with a diagonal swipe and reports where the cursor ends up.
    private static func cursorAfterSwipe() -> CGPoint {
        let pointer = PointerState()
        let recognizer = GestureRecognizer { pointer.apply($0) }
        recognizer.surfaceSize = CGSize(width: PhoneMetrics.size.width - PhoneMetrics.surfaceMargin * 2,
                                         height: PhoneMetrics.trackpad)

        func frame(_ action: TouchAction, _ x: CGFloat, _ y: CGFloat, _ t: Double) -> TouchFrame {
            TouchFrame(action: action, touches: [TouchPoint(x: x, y: y, id: 0)], timeMs: t)
        }

        recognizer.handle(frame(.down, 120, 300, 0))
        // Sixteen frames of a steady diagonal sweep, at 60Hz.
        for step in 1...16 {
            let t = Double(step) * 16
            recognizer.handle(frame(.move, 120 + CGFloat(step) * 9, 300 - CGFloat(step) * 5, t))
        }
        recognizer.handle(frame(.up, 264, 220, 17 * 16))

        print("cursor after swipe: \(Int(pointer.position.x)), \(Int(pointer.position.y))")
        return pointer.position
    }

    private static func parseOutDir() -> URL {
        var out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("out")
        var args = Array(CommandLine.arguments.dropFirst())
        while let first = args.first {
            args.removeFirst()
            if first == "--out", let value = args.first {
                args.removeFirst()
                out = URL(fileURLWithPath: value)
            }
        }
        return out
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }
}
