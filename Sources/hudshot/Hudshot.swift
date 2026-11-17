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

        // --icons makes the theme icons from the mustard one, and nothing else.
        if CommandLine.arguments.contains("--icons") {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            try ThemeIcons.make(root: root, sheet: outDir.appendingPathComponent("theme-icons.png"))
            return
        }

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
        let surfaceH = Int((PhoneMetrics.trackpad - PhoneMetrics.padHeader) * scale)
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

        // The map held up alone: its tile is lit, the others dimmed.
        try write(PhoneScreen(surface: plain, solo: .map),
                  to: outDir, "phone-solo", scale: scale)

        // The GLASSES section: arranging, and the view cleared.
        try write(PhoneScreen(surface: plain, arrangement: fullGrid, editing: true),
                  to: outDir, "phone-arranging", scale: scale)
        var someHidden = fullGrid
        someHidden.toggleHidden(.note)
        try write(PhoneScreen(surface: plain, arrangement: someHidden),
                  to: outDir, "phone-glasses", scale: scale)
        try write(PhoneScreen(surface: plain, arrangement: fullGrid, clearView: true),
                  to: outDir, "phone-clear", scale: scale)

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

        // Three tabs, the cursor on an inactive one: its close mark is up, the buttons are out.
        var tabbed = HudSnapshot(cursor: nil)
        tabbed.browser.tabs = ["YouTube", "UIKit | Apple Developer Documentation",
                               "xreal air 2 ultra - Google Search"]
        tabbed.browser.activeTab = 1
        let tabLayout = GlassesLayout(tabCount: 3, activeTab: 1)
        let tabBar = tabLayout.barFrame!
        let segments = BrowserMetrics.tabSegments(barWidth: tabBar.width, count: 3, active: 1)
        tabbed.cursor = CGPoint(x: tabBar.minX + segments[2].x + 120, y: tabBar.midY)
        try write(GlassesScreen(snapshot: tabbed), to: outDir, "glasses-tabs", scale: 1)

        // Fullscreen: the page has the canvas, nothing of ours on it.
        var full = HudSnapshot(cursor: nil)
        full.browser.isFullscreen = true
        try write(GlassesScreen(snapshot: full,
                                browserContent: AnyView(FullscreenStandIn())),
                  to: outDir, "glasses-fullscreen", scale: 1)

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

        // Each panel alone, as a held tile on the phone shows it.
        var still = HudSnapshot(cursor: nil)
        still.sky = previewSky
        for kind in HudPanelKind.allCases where kind != .mac {
            try write(GlassesScreen(snapshot: still, arrangement: fullGrid, solo: kind),
                      to: outDir, "glasses-solo-\(kind.rawValue)", scale: 1)
        }
        // The sky with planes and the station up, Saturn picked; then south with the zodiac,
        // and zoomed in on a plane.
        var skyStill = still
        skyStill.overhead = .preview
        skyStill.skyView.selected = "body:SATURN"
        try write(GlassesScreen(snapshot: skyStill, arrangement: fullGrid, solo: .sky),
                  to: outDir, "glasses-solo-sky", scale: 1)
        var south = skyStill
        south.minimap.heading = 175
        south.skyView.selected = "sign:\(Zodiac.pisces.rawValue)"
        try write(GlassesScreen(snapshot: south, arrangement: fullGrid, solo: .sky),
                  to: outDir, "glasses-sky-south", scale: 1)
        var close = skyStill
        close.skyView.fov = 64
        close.skyView.tilt = 6
        close.skyView.selected = "plane:4951d6"
        try write(GlassesScreen(snapshot: close, arrangement: fullGrid, solo: .sky),
                  to: outDir, "glasses-sky-close", scale: 1)
        var lookingUp = skyStill
        lookingUp.skyView.fov = 160
        lookingUp.skyView.tilt = 40
        lookingUp.skyView.layers.insert(.grid)
        lookingUp.skyView.selected = "iss"
        try write(GlassesScreen(snapshot: lookingUp, arrangement: fullGrid, solo: .sky),
                  to: outDir, "glasses-sky-wide", scale: 1)

        // STREET: a row of widgets along the top, one app under it; and along the bottom.
        let street = HudScene.presets[1].arrangement
        try write(GlassesScreen(snapshot: skyStill, arrangement: street), to: outDir, "glasses-street", scale: 1)
        var streetBottom = street
        streetBottom.setStrip(.bottom)
        streetBottom.toggleHidden(.browser)
        try write(GlassesScreen(snapshot: skyStill, arrangement: streetBottom),
                  to: outDir, "glasses-street-bottom", scale: 1)
        try write(PhoneScreen(surface: plain, arrangement: street), to: outDir, "phone-street", scale: scale)
        try write(PhoneScreen(surface: plain, arrangement: street, editing: true),
                  to: outDir, "phone-street-arranging", scale: scale)

        // The phone's lower half: pointing it as a remote, and the fullscreen apps' own pads.
        try write(PhoneScreen(surface: touched, pad: .remote), to: outDir, "phone-remote", scale: scale)
        var phoneSky = skyStill
        phoneSky.skyView.selected = "plane:4951d6"
        try write(PhoneScreen(surface: plain, solo: .sky, pad: .app, appSnapshot: phoneSky),
                  to: outDir, "phone-pad-sky", scale: scale)
        for kind in [HudPanelKind.music, .clock, .captions, .note, .prompter, .photos, .camera] {
            try write(PhoneScreen(surface: plain, solo: kind, pad: .app, appSnapshot: skyStill),
                      to: outDir, "phone-pad-\(kind.rawValue)", scale: scale)
        }
        var magnifying = skyStill
        magnifying.camera.mode = .magnify
        magnifying.camera.zoom = 4
        magnifying.camera.frozen = true
        try write(PhoneScreen(surface: plain, solo: .camera, pad: .app, appSnapshot: magnifying),
                  to: outDir, "phone-pad-camera-magnifier", scale: scale)

        // YouTube held up alone: the browse grid with the cursor on a card, then the player.
        var tube = still
        tube.youtube = .preview
        tube.cursor = CGPoint(x: HudTheme.safeInset + YouTubeAppLayout.cardFrame(slot: 1).midX,
                              y: HudTheme.safeInset + YouTubeAppLayout.cardFrame(slot: 1).midY - 40)
        try write(GlassesScreen(snapshot: tube, arrangement: fullGrid, solo: .youtube),
                  to: outDir, "glasses-youtube-browse", scale: 1)
        tube.youtube.page = .player
        tube.cursor = nil
        try write(GlassesScreen(snapshot: tube, arrangement: fullGrid, solo: .youtube),
                  to: outDir, "glasses-youtube-player", scale: 1)
        var paused = tube
        paused.youtube.isPlaying = false
        try write(GlassesScreen(snapshot: paused, arrangement: fullGrid, solo: .youtube),
                  to: outDir, "glasses-youtube-paused", scale: 1)
        var tubeGrid = fullGrid
        tubeGrid.place(.youtube, at: .slot(.right, 0))
        tube.cursor = nil
        try write(GlassesScreen(snapshot: tube, arrangement: tubeGrid),
                  to: outDir, "glasses-youtube-widget", scale: 1)
        // The same with a live layer under them, as on the glasses: the video must show
        // through each one's clear place.
        let liveVideo = AnyView(LinearGradient(colors: [.teal, .indigo], startPoint: .leading, endPoint: .trailing))
        try write(GlassesScreen(snapshot: tube, arrangement: tubeGrid, youtubeContent: liveVideo),
                  to: outDir, "glasses-youtube-widget-live", scale: 1)
        var liveBrowse = tube
        liveBrowse.youtube.page = .browse
        try write(GlassesScreen(snapshot: liveBrowse, arrangement: fullGrid, solo: .youtube, youtubeContent: liveVideo),
                  to: outDir, "glasses-youtube-browse-live", scale: 1)
        try write(GlassesScreen(snapshot: paused, arrangement: fullGrid, solo: .youtube, youtubeContent: liveVideo),
                  to: outDir, "glasses-youtube-paused-live", scale: 1)
        try write(PhoneScreen(surface: plain, solo: .youtube, pad: .app, appSnapshot: tube),
                  to: outDir, "phone-pad-youtube", scale: scale)
        var tubeSearch = tube
        tubeSearch.youtube.query = "lofi hip hop"
        tubeSearch.youtube.isEditingQuery = true
        try write(PhoneScreen(surface: plain, solo: .youtube, pad: .app, appSnapshot: tubeSearch),
                  to: outDir, "phone-pad-youtube-search", scale: scale)

        // A running timer in the clock app, the cursor on it.
        var timing = still
        var timer = HudTimer(setSeconds: 25 * 60)
        let now = Date()
        timer.toggle(at: now.addingTimeInterval(-7 * 60 - 12))
        timing.timer = timer.reading(at: now)
        timing.cursor = CGPoint(x: HudTheme.safeInset + ClockAppLayout.timerCard.midX,
                                y: HudTheme.safeInset + ClockAppLayout.timerCard.midY)
        try write(GlassesScreen(snapshot: timing, arrangement: fullGrid, solo: .clock),
                  to: outDir, "glasses-solo-clock-timer", scale: 1)

        // The grid: six widgets and the browser; then the browser over the right side.
        try write(GlassesScreen(snapshot: still, arrangement: fullGrid),
                  to: outDir, "glasses-grid", scale: 1)
        var takeover = fullGrid
        takeover.place(.browser, at: .slot(.right, 0))
        try write(GlassesScreen(snapshot: still, arrangement: takeover),
                  to: outDir, "glasses-takeover", scale: 1)
        var open = fullGrid
        open.remove(.browser)
        try write(GlassesScreen(snapshot: still, arrangement: open),
                  to: outDir, "glasses-open-middle", scale: 1)

        // The Mac beside the browser, then alone; and the waiting card before HudCast answers.
        var mac = HudSnapshot(cursor: nil)
        mac.desktop = .preview
        var both = HudArrangement.standard
        both.place(.mac, at: .middle)
        both.place(.browser, at: .slot(.left, 0))
        try write(GlassesScreen(snapshot: mac, arrangement: both),
                  to: outDir, "glasses-mac-split", scale: 1)
        try write(GlassesScreen(snapshot: mac, arrangement: both, solo: .mac),
                  to: outDir, "glasses-solo-mac", scale: 1)
        try write(GlassesScreen(snapshot: HudSnapshot(cursor: nil), visible: [.mac, .clock],
                                placeholders: false),
                  to: outDir, "glasses-mac-waiting", scale: 1)
        var macWindow = HudSnapshot.Desktop.preview
        macWindow.source?.window = 12
        try write(PhoneScreen(surface: plain, arrangement: HudArrangement(visible: [.browser, .mac, .map]),
                              desktop: macWindow, showsWindows: true),
                  to: outDir, "phone-windows", scale: scale)

        // Maps: searching, with the cursor on the second result; then following a route.
        var searching = HudSnapshot(cursor: nil)
        searching.maps = .previewSearch
        searching.cursor = CGPoint(x: MapsLayout(resultCount: 4).resultFrame(1).midX + 120,
                                   y: MapsLayout(resultCount: 4).resultFrame(1).midY)
        try write(GlassesScreen(snapshot: searching, visible: [.map], solo: .map),
                  to: outDir, "glasses-maps-search", scale: 1)
        var navigating = HudSnapshot(cursor: nil)
        navigating.maps = .previewNavigation
        try write(GlassesScreen(snapshot: navigating, visible: [.map], solo: .map),
                  to: outDir, "glasses-maps-route", scale: 1)

        if live {
            let (snapshot, ground, soloGround) = try liveSnapshot()
            try write(GlassesScreen(snapshot: snapshot, mapGround: ground),
                      to: outDir, "glasses-live", scale: 1)
            if let soloGround {
                var solo = snapshot
                solo.minimap.groundSpanMetres = soloGround.span
                try write(GlassesScreen(snapshot: solo, visible: [.map], solo: .map,
                                        mapGround: soloGround.image),
                          to: outDir, "glasses-live-solo-map", scale: 1)
            }
        }
        try write(GlassesScreen(snapshot: HudSnapshot(cursor: nil),
                                visible: [.clock, .weather, .map]),
                  to: outDir, "glasses-glance", scale: 1)

        // The Apps Center: each app in the centre, between the widgets.
        var centreStill = still
        centreStill.cursor = nil
        for kind in HudPanelKind.apps where !kind.isBig {
            var arranged = HudArrangement(left: [.clock, .calendar, .weather], right: [.browser, .music, .note])
            arranged.setCentre(kind)
            try write(GlassesScreen(snapshot: centreStill, arrangement: arranged),
                      to: outDir, "glasses-centre-\(kind.rawValue)", scale: 1)
        }
        // Full screen: the month, the gallery, the teleprompter.
        for kind in [HudPanelKind.calendar, .photos, .prompter, .camera] {
            try write(GlassesScreen(snapshot: centreStill, arrangement: fullGrid, solo: kind),
                      to: outDir, "glasses-solo-\(kind.rawValue)", scale: 1)
        }
        // The camera: the magnifier held still and brighter, recording in a slot, and paused.
        var magnifier = centreStill
        magnifier.camera.mode = .magnify
        magnifier.camera.zoom = 4
        magnifier.camera.frozen = true
        magnifier.camera.bright = true
        try write(GlassesScreen(snapshot: magnifier, arrangement: fullGrid, solo: .camera),
                  to: outDir, "glasses-solo-camera-magnifier", scale: 1)
        var recording = centreStill
        recording.camera.mode = .video
        recording.camera.recordingSince = Date().addingTimeInterval(-83)
        var slotted = HudArrangement(left: [.clock, .camera, .weather], right: [.browser, .music, .note])
        slotted.setCentre(.map)
        try write(GlassesScreen(snapshot: recording, arrangement: slotted),
                  to: outDir, "glasses-camera-widget-recording", scale: 1)
        var cameraPaused = centreStill
        cameraPaused.camera.status = .paused
        var centred = HudArrangement(left: [.clock, .calendar, .weather], right: [.browser, .music, .note])
        centred.setCentre(.camera)
        try write(GlassesScreen(snapshot: cameraPaused, arrangement: centred),
                  to: outDir, "glasses-centre-camera-paused", scale: 1)

        // Every theme colour: the phone and the glasses, then back to mustard.
        for theme in ThemeColor.allCases where theme != .mustard {
            ThemeStore.shared.color = theme
            var config = HalftoneConfig.miniMateDefault
            config.colorway = theme.colorway
            let surface = try renderer.render(width: surfaceW, height: surfaceH, config: config)
            try write(PhoneScreen(surface: surface), to: outDir, "theme-\(theme.rawValue)-phone", scale: scale)
            var arranged = HudArrangement(left: [.clock, .calendar, .weather], right: [.browser, .music, .note])
            arranged.setCentre(.sky)
            try write(GlassesScreen(snapshot: centreStill, arrangement: arranged),
                      to: outDir, "theme-\(theme.rawValue)-glasses", scale: 1)
        }
        ThemeStore.shared.color = .mustard

        print("\nimages in \(outDir.path)")
    }

    /// All six slots full, the browser in the middle.
    static let fullGrid = HudArrangement(left: [.clock, .weather, .map],
                                         right: [.music, .sky, .note],
                                         centre: .init(kind: .browser))

    /// Lisbon at ten at night in mid-November, so the stills have stars.
    static let previewSky: HudSnapshot.Sky = {
        let lisbon = TimeZone(identifier: "Europe/Lisbon")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = lisbon
        let night = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 22))!
        return SkyModel.compute(at: night, latitude: 38.72, longitude: -9.14, timeZone: lisbon)
    }()

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
    private static func liveSnapshot() throws
        -> (HudSnapshot, Image?, (image: Image, span: Double)?) {
        let lisbon = CLLocationCoordinate2D(latitude: 38.7139, longitude: -9.1334)
        var snapshot = HudSnapshot(cursor: nil)

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var weather: HudSnapshot.Weather?
        nonisolated(unsafe) var ground: CGImage?
        nonisolated(unsafe) var soloGround: CGImage?
        // The same sizes the phone asks for: the column panel's raster, and the full canvas's
        // (its diagonal at the fixed zoom, plus walking room).
        let minimap = snapshot.minimap
        let ppm = minimap.pointsPerMetre
        let columnSpan = Double(minimap.spanMetres) * HudSnapshot.Minimap.groundOversize
        let soloSpan = Double(hypot(1920.0 - 128, 1080.0 - 128)) / ppm + 300
        nonisolated(unsafe) var failure: Error?

        Task.detached {
            do {
                weather = try await OpenMeteoWeatherProvider()
                    .weather(at: lisbon, placeName: "Lisbon")
                ground = try await MapSnapshotProvider()
                    .snapshot(centre: lisbon, spanMetres: columnSpan,
                              size: CGSize(width: columnSpan * ppm, height: columnSpan * ppm))
                soloGround = try await MapSnapshotProvider()
                    .snapshot(centre: lisbon, spanMetres: soloSpan,
                              size: CGSize(width: soloSpan * ppm, height: soloSpan * ppm),
                              scale: 1)
            } catch {
                failure = error
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            print("live: timed out")
            return (snapshot, nil, nil)
        }
        if let failure {
            print("live: \(failure)")
            return (snapshot, nil, nil)
        }

        if let weather {
            snapshot.weather = weather
            print("live weather: \(weather.temperature)\u{00B0} \(weather.condition)")
        }
        print("live map: \(ground.map { "\($0.width)x\($0.height)" } ?? "none")")
        return (snapshot, ground.map { Image(decorative: $0, scale: 2) },
                soloGround.map { (Image(decorative: $0, scale: 1), soloSpan) })
    }

    /// A video frame's worth of stand-in, for the fullscreen still.
    struct FullscreenStandIn: View {
        var body: some View {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.05), .black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "play.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 18) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(Color.red).frame(width: g.size.width * 0.34)
                        }
                    }
                    .frame(height: 6)
                    Text("12:41 / 37:02")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(48)
            }
        }
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
