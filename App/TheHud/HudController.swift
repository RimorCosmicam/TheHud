import SwiftUI
import Combine
import CoreLocation
import HudCore

/// The one piece of state both scenes read.
///
/// The phone scene owns the surface and the input; the glasses scene only draws. Keeping the
/// model here rather than in either scene is what lets the glasses come and go — unplugging the
/// cable tears down a scene, not the session.
@MainActor
final class HudController: ObservableObject {
    static let shared = HudController()

    @Published private(set) var snapshot = HudSnapshot(cursor: nil)
    @Published private(set) var contacts: [TouchPoint] = []
    @Published var mode: GlassesScreen.Mode = .browser
    @Published var config: HalftoneConfig = .miniMateDefault

    // Real data. Each panel degrades on its own: no calendar access drops one line, no location
    // leaves the map blank, a failed weather fetch keeps the last reading. None of them can take
    // the HUD down, because a HUD that disappears when a service is unreachable is worse than one
    // that is briefly out of date.
    private let calendar = CalendarProvider()
    private let location = LocationProvider()
    private let weatherProvider: WeatherProviding = OpenMeteoWeatherProvider()
    private let maps = MapSnapshotProvider()

    @Published private(set) var mapGround: Image?
    @Published private(set) var browserContent: AnyView?

    private var clockTimer: Timer?
    private var lastWeatherFetch: Date = .distantPast
    private var lastMapFetch: Date = .distantPast
    private var lastMapCentre: CLLocationCoordinate2D?

    private let pointer = PointerState()
    private let momentum = MomentumScroller()
    private var momentumTimer: Timer?

    let rail = ScrollRail()
    private(set) lazy var recognizer: GestureRecognizer = {
        let recognizer = GestureRecognizer { [weak self] event in
            self?.handle(event)
        }
        recognizer.onTouchPointsUpdated = { [weak self] points in
            self?.contacts = points
        }
        return recognizer
    }()

    private init() {
        snapshot.cursor = pointer.position
        snapshot.clock = .now()
    }

    /// Called once the phone scene is on screen.
    func start() {
        tickClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { self.tickClock() }
        }

        Task {
            if await calendar.requestAccess() { tickClock() }
        }

        location.onUpdate = { [weak self] minimap, coordinate in
            MainActor.assumeIsolated { self?.locationChanged(minimap, coordinate) }
        }
        location.start()

        openBrowser(URL(string: "https://developer.apple.com/documentation/uikit")!)
    }

    private func tickClock() {
        var clock = HudSnapshot.Clock.now()
        if let next = calendar.nextEvent() {
            clock.nextEvent = next.title
            clock.nextEventTime = next.time
        }
        snapshot.clock = clock
    }

    private func locationChanged(_ minimap: HudSnapshot.Minimap,
                                 _ coordinate: CLLocationCoordinate2D) {
        snapshot.minimap = minimap

        // Weather every fifteen minutes: it does not change faster than that, and the request
        // carries coordinates to a third party, so fewer is better.
        if Date().timeIntervalSince(lastWeatherFetch) > 900 {
            lastWeatherFetch = Date()
            let place = minimap.place
            Task { [weak self] in
                guard let self else { return }
                if let weather = try? await self.weatherProvider.weather(at: coordinate,
                                                                         placeName: place) {
                    self.snapshot.weather = weather
                }
            }
        }

        // The map only needs refetching once you have actually gone somewhere.
        let movedFar = lastMapCentre.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude,
                                           longitude: coordinate.longitude)) > 80
        } ?? true

        if movedFar, Date().timeIntervalSince(lastMapFetch) > 20 {
            lastMapFetch = Date()
            lastMapCentre = coordinate
            Task { [weak self] in
                guard let self else { return }
                if let ground = try? await self.maps.snapshot(
                    centre: coordinate,
                    spanMetres: Double(minimap.spanMetres) * 2,
                    size: CGSize(width: 470, height: 492)) {
                    self.mapGround = Image(decorative: ground, scale: 2)
                }
            }
        }
    }

    func openBrowser(_ url: URL) {
        snapshot.browser = HudSnapshot.Browser(
            url: (url.host ?? "") + url.path,
            title: "",
            tabs: snapshot.browser.tabs.isEmpty ? ["New tab"] : snapshot.browser.tabs,
            activeTab: snapshot.browser.activeTab)

        browserContent = AnyView(
            WebContentView(
                url: url,
                onTitleChange: { [weak self] title in
                    MainActor.assumeIsolated {
                        self?.snapshot.browser.title = title
                        guard let self else { return }
                        var tabs = self.snapshot.browser.tabs
                        if tabs.indices.contains(self.snapshot.browser.activeTab) {
                            tabs[self.snapshot.browser.activeTab] = title
                            self.snapshot.browser.tabs = tabs
                        }
                    }
                },
                onURLChange: { [weak self] shown in
                    MainActor.assumeIsolated { self?.snapshot.browser.url = shown }
                })
        )
    }

    func surfaceSizeChanged(to size: CGSize) {
        recognizer.surfaceSize = size
    }

    private func handle(_ event: GestureEvent) {
        pointer.apply(event)

        if case let .scrollFling(vx, vy) = event {
            startMomentum(vx: vx, vy: vy)
        } else if case .move = event {
            momentum.stop()
        }

        snapshot.cursor = pointer.position
    }

    /// MiniMate ran the fling on a coroutine. A timer is the same shape; the scroller itself is
    /// stepped explicitly either way, which is what makes it testable.
    private func startMomentum(vx: Float, vy: Float) {
        momentumTimer?.invalidate()
        guard momentum.startFling(velocityX: vx, velocityY: vy,
                                  friction: recognizer.settings.momentumFriction,
                                  scrollSpeed: recognizer.settings.scrollSpeed,
                                  isNatural: recognizer.settings.naturalScrolling)
        else { return }

        momentumTimer = Timer.scheduledTimer(withTimeInterval: MomentumScroller.frameInterval,
                                             repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                if let step = self.momentum.step() {
                    self.pointer.apply(.scroll(v: step.v, h: step.h))
                }
                if !self.momentum.isRunning { timer.invalidate() }
            }
        }
    }

    // The rail is outside the recogniser, exactly as it is in MiniMate: the pointer rejects edge
    // touches so the two never fight over the same thumb.
    func railBegan(at y: CGFloat) {
        momentum.stop()
        rail.begin(at: y)
    }

    func railMoved(to y: CGFloat) {
        if let ticks = rail.move(to: y) {
            pointer.apply(.scroll(v: ticks, h: 0))
        }
    }

    func railEnded() { rail.end() }

    func cornerTapped() { pointer.apply(.rightClick) }
}
