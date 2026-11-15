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

    @Published private(set) var snapshot = HudSnapshot.blank
    @Published private(set) var contacts: [TouchPoint] = []
    @Published private(set) var visible: Set<HudPanelKind>
    @Published var config: HalftoneConfig = .miniMateDefault
    @Published var trackpad = TouchpadSettings()

    /// While the glasses are on, the phone must not auto-lock: locking backgrounds the app, and
    /// a backgrounded app's external display goes black.
    @Published var glassesConnected = false {
        didSet { UIApplication.shared.isIdleTimerDisabled = glassesConnected }
    }

    @Published private(set) var favorites: [Favorite]
    @Published var showingSettings = false
    @Published private(set) var railActive = false
    @Published var cornerPressed = false

    /// Where keystrokes go while the keyboard is up.
    enum KeyboardTarget { case address, page }
    @Published private(set) var keyboardTarget: KeyboardTarget?
    /// The invisible text field's contents. For the address bar it is the draft itself; for the
    /// page it is a proxy that is diffed into insertions and deletions.
    @Published private(set) var draft = ""

    let browser = WebBrowser()

    // Real data. Each panel degrades on its own: no calendar access drops one line, no location
    // leaves the map blank, a failed weather fetch keeps the last reading. None of them can take
    // the HUD down, because a HUD that disappears when a service is unreachable is worse than one
    // that is briefly out of date.
    private let calendar = CalendarProvider()
    private let location = LocationProvider()
    private let weatherProvider: WeatherProviding = OpenMeteoWeatherProvider()
    private let maps = MapSnapshotProvider()

    @Published private(set) var mapGround: Image?

    private var clockTimer: Timer?
    private var lastWeatherFetch: Date = .distantPast
    private var lastMapFetch: Date = .distantPast
    /// Where the current map raster is centred. The raster slides by the wearer's distance from
    /// here until a new one is fetched around where they are now.
    private var groundCentre: CLLocationCoordinate2D?
    private var lastCoordinate: CLLocationCoordinate2D?
    private var mapFetchInFlight = false

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
        let stored = UserDefaults.standard.stringArray(forKey: Self.visibleKey)
        visible = stored.map { Set($0.compactMap(HudPanelKind.init(rawValue:))) }
            ?? Set(HudPanelKind.allCases)
        if let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
           let stored = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = stored
        } else {
            favorites = Favorite.defaults
        }
        snapshot.cursor = pointer.position
        snapshot.clock = .now()
        loadSettings()

        browser.onChange = { [weak self] state in self?.browserChanged(state) }
        browser.homeHTML = { [weak self] in HomePage.html(self?.favorites ?? Favorite.defaults) }
    }

    private static let visibleKey = "visiblePanels"
    private static let favoritesKey = "favorites"

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

        browser.goHome()
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

        lastCoordinate = coordinate
        applyGroundOffset()

        // A new raster once the old one is running out under the marker. It covers
        // `groundOversize` times the panel's span, and turning needs the panel's diagonal of
        // that, so about a fifth of the span is the walking room either way.
        let walked = groundCentre.map { metres(from: $0, to: coordinate) } ?? .infinity
        let room = Double(minimap.spanMetres) * 0.2
        if walked > room, !mapFetchInFlight, Date().timeIntervalSince(lastMapFetch) > 3 {
            lastMapFetch = Date()
            mapFetchInFlight = true
            let span = Double(minimap.spanMetres) * HudSnapshot.Minimap.groundOversize
            // Panel points per metre, times the span, so the raster is drawn at its own size.
            let side = 470 * HudSnapshot.Minimap.groundOversize
            Task { [weak self] in
                guard let self else { return }
                defer { self.mapFetchInFlight = false }
                if let ground = try? await self.maps.snapshot(
                    centre: coordinate, spanMetres: span,
                    size: CGSize(width: side, height: side)) {
                    self.mapGround = Image(decorative: ground, scale: 2)
                    self.groundCentre = coordinate
                    self.applyGroundOffset()
                }
            }
        }
    }

    /// The wearer's position relative to the raster's centre, east and north in metres.
    private func applyGroundOffset() {
        guard let centre = groundCentre, let here = lastCoordinate else { return }
        let metresPerDegree = 111_320.0
        snapshot.minimap.groundOffsetNorth = (here.latitude - centre.latitude) * metresPerDegree
        snapshot.minimap.groundOffsetEast = (here.longitude - centre.longitude) * metresPerDegree
            * cos(centre.latitude * .pi / 180)
    }

    private func metres(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    // ------------------------------------------------------------------ browser

    private func browserChanged(_ state: WebBrowser.State) {
        var browser = snapshot.browser
        browser.isHome = state.isHome
        browser.isFavorite = !state.isHome && favorites.contains {
            $0.site == Favorite.site(of: state.absoluteURL)
        }
        if keyboardTarget != .address { browser.url = state.url }
        browser.title = state.title
        browser.canGoBack = state.canGoBack
        browser.canGoForward = state.canGoForward
        browser.loading = state.loading
        // One tab for now: it carries the page's title.
        browser.tabs = [state.title.isEmpty ? "New tab" : state.title]
        browser.activeTab = 0
        snapshot.browser = browser
    }

    /// Every button on the phone lands here.
    func perform(_ action: PhoneAction) {
        switch action {
        case .back: browser.back()
        case .forward: browser.forward()
        case .reload: browser.reload()
        case .home: browser.goHome()
        case .favorite: toggleFavorite()
        case .address: keyboardTarget == .address ? endTyping() : beginAddressEditing()
        case .keyboard: keyboardTarget == nil ? beginPageTyping() : endTyping()
        case .settings: showingSettings = true
        case let .toggle(kind):
            if visible.contains(kind) { visible.remove(kind) } else { visible.insert(kind) }
            UserDefaults.standard.set(visible.map(\.rawValue), forKey: Self.visibleKey)
        }
    }

    /// Star the current site, or unstar it.
    private func toggleFavorite() {
        let state = browser.state
        guard !state.isHome, !state.absoluteURL.isEmpty else { return }
        let site = Favorite.site(of: state.absoluteURL)
        if let index = favorites.firstIndex(where: { $0.site == site }) {
            favorites.remove(at: index)
        } else {
            // The site's front page, not the article that happened to be open.
            let url = URL(string: state.absoluteURL)
            let root = url.flatMap { u in u.host.map { "\(u.scheme ?? "https")://\($0)" } }
                ?? state.absoluteURL
            let title = state.title.isEmpty ? site : Self.shortTitle(state.title, site: site)
            favorites.append(Favorite(title: title, url: root))
        }
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
        snapshot.browser.isFavorite = favorites.contains { $0.site == site }
    }

    /// "Some video - YouTube" is a page title; the tile wants "YouTube". Sites put their own
    /// name at one end after a separator, so take the end that looks like the site.
    private static func shortTitle(_ title: String, site: String) -> String {
        let separators = [" - ", " | ", " \u{2013} ", " \u{2014} ", " · "]
        for separator in separators where title.contains(separator) {
            let parts = title.components(separatedBy: separator)
            let key = site.split(separator: ".").first.map(String.init)?.lowercased() ?? site
            if let match = parts.first(where: { $0.lowercased().contains(key) }) { return match }
            return parts.last ?? title
        }
        return title.count > 18 ? (site.split(separator: ".").first.map(String.init)?.capitalized ?? title) : title
    }

    private var layout: GlassesLayout { GlassesLayout(visible: visible) }

    /// A left click wherever the cursor is. The glasses take no touches, so this is arithmetic
    /// against the layout the canvas was drawn with.
    private func click() {
        guard let cursor = snapshot.cursor else { return }
        switch layout.hitTest(cursor) {
        case .back: browser.back()
        case .forward: browser.forward()
        case .reload: browser.reload()
        case .address: beginAddressEditing()
        case let .page(point):
            if keyboardTarget == .address { endTyping() }
            Task {
                if await browser.click(at: point) { beginPageTyping() }
            }
        case .none: break
        }
    }

    /// Scrolls the page under the cursor, or the page as a whole when the cursor is elsewhere:
    /// the rail should scroll the page wherever the pointer happens to be parked.
    private func scrollPage(_ ticks: Int) {
        guard ticks != 0, let content = layout.contentFrame else { return }
        let point: CGPoint
        if let cursor = snapshot.cursor, case let .page(p) = layout.hitTest(cursor) {
            point = p
        } else {
            point = CGPoint(x: content.width / 2, y: content.height / 2)
        }
        browser.scroll(ticks: ticks, at: point)
    }

    // ------------------------------------------------------------------ keyboard

    /// Starts the page proxy with one invisible character, so a backspace on an empty field
    /// still reaches the page as a deletion instead of being swallowed by an empty text field.
    private static let sentinel = "\u{200B}"

    func beginAddressEditing() {
        keyboardTarget = .address
        draft = ""
        snapshot.browser.url = ""
        snapshot.browser.isEditingAddress = true
    }

    func beginPageTyping() {
        if keyboardTarget == .address { snapshot.browser.isEditingAddress = false }
        keyboardTarget = .page
        draft = Self.sentinel
    }

    func endTyping() {
        if keyboardTarget == .address {
            snapshot.browser.isEditingAddress = false
            snapshot.browser.url = browser.state.url
        }
        keyboardTarget = nil
        draft = ""
    }

    /// The text field changed. Called by its binding.
    func draftChanged(_ new: String) {
        switch keyboardTarget {
        case .address:
            draft = new
            snapshot.browser.url = new
        case .page:
            let sentinel = Self.sentinel
            let old = draft.hasPrefix(sentinel) ? String(draft.dropFirst()) : draft
            if new.hasPrefix(sentinel) {
                send(from: old, to: String(new.dropFirst()))
                draft = new
            } else {
                // The sentinel went: one backspace past everything typed here.
                send(from: old, to: new)
                browser.deleteBackward(1)
                draft = sentinel + new
            }
        case nil:
            draft = new
        }
    }

    private func send(from old: String, to new: String) {
        let edit = TextEdit.between(old, new)
        browser.deleteBackward(edit.deletes)
        if !edit.insert.isEmpty { browser.insert(edit.insert) }
    }

    func submitTyping() {
        switch keyboardTarget {
        case .address:
            if let url = AddressInput.url(from: draft) { browser.load(url) }
            endTyping()
        case .page:
            browser.submit()
            endTyping()
        case nil:
            break
        }
    }

    // ------------------------------------------------------------------ settings

    func settingsChanged() {
        recognizer.settings = trackpad
        rail.scrollSpeed = trackpad.scrollSpeed
        rail.naturalScrolling = trackpad.naturalScrolling
        let defaults = UserDefaults.standard
        defaults.set(trackpad.trackingSpeed, forKey: "trackingSpeed")
        defaults.set(trackpad.scrollSpeed, forKey: "scrollSpeed")
        defaults.set(trackpad.naturalScrolling, forKey: "naturalScrolling")
        defaults.set(trackpad.tapToClick, forKey: "tapToClick")
        defaults.set(trackpad.momentumScrolling, forKey: "momentumScrolling")
        defaults.set(config.colorway.label, forKey: "palette")
        defaults.set(config.pitch, forKey: "pitch")
        defaults.set(config.contrast, forKey: "contrast")
    }

    static let palettes: [Colorway] = [.mustardFlat, .mono, .paperFlat, .signal]

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "trackingSpeed") != nil {
            trackpad.trackingSpeed = defaults.float(forKey: "trackingSpeed")
            trackpad.scrollSpeed = defaults.float(forKey: "scrollSpeed")
            trackpad.naturalScrolling = defaults.bool(forKey: "naturalScrolling")
            trackpad.tapToClick = defaults.bool(forKey: "tapToClick")
            trackpad.momentumScrolling = defaults.bool(forKey: "momentumScrolling")
            config.pitch = defaults.float(forKey: "pitch")
            config.contrast = defaults.float(forKey: "contrast")
            if let label = defaults.string(forKey: "palette"),
               let palette = Self.palettes.first(where: { $0.label == label }) {
                config.colorway = palette
            }
        }
        recognizer.settings = trackpad
        rail.scrollSpeed = trackpad.scrollSpeed
        rail.naturalScrolling = trackpad.naturalScrolling
    }

    func surfaceSizeChanged(to size: CGSize) {
        recognizer.surfaceSize = size
    }

    private func handle(_ event: GestureEvent) {
        pointer.apply(event)

        switch event {
        case let .scrollFling(vx, vy): startMomentum(vx: vx, vy: vy)
        case .move: momentum.stop()
        case .tapClick: click()
        default: break
        }

        scrollPage(pointer.drainScroll())
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
                    self.scrollPage(self.pointer.drainScroll())
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
        railActive = true
    }

    func railMoved(to y: CGFloat) {
        if let ticks = rail.move(to: y) {
            pointer.apply(.scroll(v: ticks, h: 0))
            scrollPage(pointer.drainScroll())
        }
    }

    func railEnded() {
        rail.end()
        railActive = false
    }

    func cornerTapped() { pointer.apply(.rightClick) }
}
