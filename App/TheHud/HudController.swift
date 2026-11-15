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
    /// What is on the glasses and where, as arranged on the phone. Saved.
    @Published private(set) var arrangement: HudArrangement {
        didSet {
            guard arrangement != oldValue else { return }
            if let data = try? JSONEncoder().encode(arrangement) {
                UserDefaults.standard.set(data, forKey: Self.arrangementKey)
            }
            panelsChanged()
        }
    }
    /// One panel held up on its own, filling the glasses. Not saved: it is a moment's focus,
    /// and the arrangement is what comes back.
    @Published private(set) var solo: HudPanelKind? {
        didSet { if solo != oldValue { panelsChanged() } }
    }
    /// Everything hidden, to see straight through the glasses.
    @Published private(set) var clearView = false {
        didSet { if clearView != oldValue { panelsChanged() } }
    }
    /// The phone's GLASSES section is being arranged.
    @Published private(set) var editingGlasses = false

    /// Whether a panel is on the glasses right now.
    func isOnGlasses(_ kind: HudPanelKind) -> Bool {
        if clearView { return false }
        return solo.map { $0 == kind } ?? arrangement.isShown(kind)
    }
    /// The map held up alone: it gets the whole canvas, as the Maps app.
    private var mapFillsCanvas: Bool { solo == .map && !clearView }
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
    enum KeyboardTarget { case address, page, mapSearch, mac, note }
    @Published private(set) var keyboardTarget: KeyboardTarget?
    /// The invisible text field's contents. For the address bar it is the draft itself; for the
    /// page it is a proxy that is diffed into insertions and deletions.
    @Published private(set) var draft = ""

    /// One web view per tab, so each keeps its page, scroll position and history.
    private(set) var tabs: [WebBrowser] = []
    @Published private(set) var activeTab = 0
    var browser: WebBrowser { tabs[activeTab] }

    private var cursorHideTimer: Timer?
    private var lastHover: Date = .distantPast

    // Real data. Each panel degrades on its own: no calendar access drops one line, no location
    // leaves the map blank, a failed weather fetch keeps the last reading. None of them can take
    // the HUD down, because a HUD that disappears when a service is unreachable is worse than one
    // that is briefly out of date.
    private let calendar = CalendarProvider()
    private let location = LocationProvider()
    private let weatherProvider: WeatherProviding = OpenMeteoWeatherProvider()
    private let maps = MapSnapshotProvider()
    private let mapsService = MapsService()

    // The widgets' own sources. Each starts the first time its widget is on the glasses, so
    // nothing asks for a permission the wearer has not shown they want.
    private var timer: HudTimer
    private var timerDoneAt: Date?
    private let music = MusicProvider()
    private let activityProvider = ActivityProvider()
    let captions = CaptionsEngine()
    /// The Music app's artwork for what is playing.
    @Published private(set) var artwork: Image?
    /// The activity ring's target.
    @Published var stepGoal: Int = UserDefaults.standard.object(forKey: "stepGoal") as? Int ?? 8000 {
        didSet {
            UserDefaults.standard.set(stepGoal, forKey: "stepGoal")
            activityProvider.goal = stepGoal
            snapshot.activity?.goal = stepGoal
        }
    }
    private var lastSky: Date = .distantPast
    /// HudCast on the Mac. Looks for it only while the desktop panel is on.
    let desktopLink = DesktopLink()
    /// The last click went to the Mac, so the keyboard button types there.
    private var desktopFocused = false
    /// A double-tap drag that started on the Mac's picture holds its mouse button down.
    private var desktopDragging = false
    private var lastDesktopMove: Date = .distantPast
    /// Both the browser and the desktop are on: whether the phone's strip lists the Mac's
    /// windows instead of the tabs.
    @Published private(set) var stripShowsWindows = false

    /// The Maps app's zoom: metres across a 470pt panel. Shared with the small map.
    private var mapSpan: Int = UserDefaults.standard.object(forKey: "mapSpan") as? Int ?? 300
    private var zoomRefetch: Timer?
    private var searchResults: [MapsService.Result] = []
    private var searchDebounce: Timer?
    /// The route being followed, and where the wearer is along it.
    private var tracker: NavigationTracker?
    private var routeDestination: MapsService.Result?

    @Published private(set) var mapGround: Image?

    private var clockTimer: Timer?
    private var lastWeatherFetch: Date = .distantPast
    private var lastMapFetch: Date = .distantPast
    /// Where the current map raster is centred. The raster slides by the wearer's distance from
    /// here until a new one is fetched around where they are now.
    private var groundCentre: CLLocationCoordinate2D?
    private var lastCoordinate: CLLocationCoordinate2D?
    private var mapFetchInFlight = false
    /// Metres across the raster on screen. Kept here because each location fix replaces the
    /// snapshot's minimap wholesale.
    private var groundSpan: Double = 0

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
        arrangement = Self.loadArrangement()
        timer = HudTimer(setSeconds: UserDefaults.standard.object(forKey: "timerSeconds") as? Int ?? 300)
        if let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
           let stored = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = stored
        } else {
            favorites = Favorite.defaults
        }
        snapshot.cursor = pointer.position
        snapshot.clock = .now()
        snapshot.note.text = UserDefaults.standard.string(forKey: "note") ?? ""
        snapshot.timer = timer.reading(at: Date())
        loadSettings()

        tabs = [makeTab()]
    }

    private static let arrangementKey = "arrangement"

    /// The saved arrangement; or, from before there was one, the old on/off set laid out the
    /// standard way.
    private static func loadArrangement() -> HudArrangement {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: arrangementKey),
           let stored = try? JSONDecoder().decode(HudArrangement.self, from: data) {
            return stored
        }
        if let old = defaults.stringArray(forKey: "visiblePanels") {
            let kinds = old.compactMap { HudPanelKind(rawValue: $0 == "desktop" ? "mac" : $0) }
            return HudArrangement(visible: Set(kinds))
        }
        return .standard
    }
    private static let favoritesKey = "favorites"

    /// Called once the phone scene is on screen.
    func start() {
        tickClock()
        // Every second, for the clock app's seconds hand; the other layouts only take the
        // update when the minute changes.
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.tickClock() }
        }

        Task {
            if await calendar.requestAccess() {
                lastCalendarRead = .distantPast
                tickClock()
            }
        }

        location.onUpdate = { [weak self] minimap, coordinate in
            MainActor.assumeIsolated { self?.locationChanged(minimap, coordinate) }
        }
        location.start()

        desktopLink.onChange = { [weak self] desktop in self?.snapshot.desktop = desktop }
        music.onChange = { [weak self] playing, artwork in
            self?.snapshot.music = playing
            self?.artwork = artwork
        }
        activityProvider.goal = stepGoal
        activityProvider.onChange = { [weak self] activity in self?.snapshot.activity = activity }
        captions.onChange = { [weak self] captions in self?.snapshot.captions = captions }
        panelsChanged()

        browser.goHome()
    }

    private var lastCalendarRead: Date = .distantPast
    private var calendarNext: (title: String, time: String)?
    private var calendarAgenda: [HudSnapshot.Clock.Event] = []

    private func tickClock() {
        var clock = HudSnapshot.Clock.now()
        var calendarChanged = false
        if Date().timeIntervalSince(lastCalendarRead) > 30 {
            lastCalendarRead = Date()
            calendarNext = calendar.nextEvent()
            calendarAgenda = calendar.agenda()
            calendarChanged = true
        }
        clock.nextEvent = calendarNext?.title
        clock.nextEventTime = calendarNext?.time
        clock.agenda = calendarAgenda
        // A redraw a second is for the clock app alone.
        tickWidgets()
        guard isOnGlasses(.clock) && solo == .clock || calendarChanged
                || clock.time != snapshot.clock.time else { return }
        snapshot.clock = clock
    }

    private func locationChanged(_ minimap: HudSnapshot.Minimap,
                                 _ coordinate: CLLocationCoordinate2D) {
        var minimap = minimap
        minimap.spanMetres = mapSpan
        minimap.route = snapshot.minimap.route
        snapshot.minimap = minimap

        // Weather every fifteen minutes: it does not change faster than that, and the request
        // carries coordinates to a third party, so fewer is better.
        if Date().timeIntervalSince(lastWeatherFetch) > 900 {
            lastWeatherFetch = Date()
            let place = minimap.place
            Task { [weak self] in
                guard let self else { return }
                if var weather = try? await self.weatherProvider.weather(at: coordinate,
                                                                         placeName: place) {
                    weather.air = try? await AirQualityProvider.air(at: coordinate)
                    self.snapshot.weather = weather
                }
            }
        }

        lastCoordinate = coordinate
        if !snapshot.sky.hasLocation { updateSky(force: true) }
        applyGroundOffset()
        if var tracker {
            snapshot.maps.navigation = tracker.update(at: coordinate)
            self.tracker = tracker
        }

        // A new raster once the old one is running out under the marker.
        let walked = groundCentre.map { metres(from: $0, to: coordinate) } ?? .infinity
        if walked > groundPlan.room, Date().timeIntervalSince(lastMapFetch) > 3 {
            fetchGround(at: coordinate)
        }
    }

    /// How big a raster the map needs, and how far the wearer can walk before it runs out.
    ///
    /// The zoom is fixed, so the raster is sized by the panel: it has to cover the panel's
    /// diagonal (the map turns) plus some walking room. The column's panel is 470pt; on its own
    /// the map has the whole canvas, which is about 1300 m of diagonal at the same zoom.
    private var groundPlan: (span: Double, room: Double, scale: CGFloat) {
        let spanMetres = Double(snapshot.minimap.spanMetres)
        if mapFillsCanvas {
            let ppm = snapshot.minimap.pointsPerMetre
            let canvas = HudTheme.glassesSize
            let inset = HudTheme.safeInset * 2
            let diagonal = Double(hypot(canvas.width - inset, canvas.height - inset)) / ppm
            // Walking room in proportion to the zoom: a street's worth close in, a district's
            // worth far out, so the raster stays a similar number of pixels either way.
            let room = max(40, spanMetres * 0.4)
            // One point per pixel: the glasses are drawn at 1x, and a 2x raster this size would
            // be a hundred megabytes for nothing.
            return (diagonal + room * 2 + spanMetres * 0.2, room, 1)
        }
        // A fifth of the span either way, the same rule as before the solo map existed.
        return (spanMetres * HudSnapshot.Minimap.groundOversize, spanMetres * 0.2, 2)
    }

    private func fetchGround(at coordinate: CLLocationCoordinate2D) {
        guard !mapFetchInFlight else { return }
        lastMapFetch = Date()
        mapFetchInFlight = true
        let plan = groundPlan
        // Panel points per metre, times the span, so the raster is drawn at its own size.
        let side = plan.span * snapshot.minimap.pointsPerMetre
        Task { [weak self] in
            guard let self else { return }
            let ground = try? await self.maps.snapshot(
                centre: coordinate, spanMetres: plan.span,
                size: CGSize(width: side, height: side), scale: plan.scale)
            self.mapFetchInFlight = false
            if let ground {
                self.mapGround = Image(decorative: ground, scale: plan.scale)
                self.groundCentre = coordinate
                self.groundSpan = plan.span
                self.applyGroundOffset()
            }
            // The map was soloed or put back while this was in flight: the raster is the
            // wrong size for what is on screen now.
            if self.groundPlan.span != plan.span, let here = self.lastCoordinate {
                self.fetchGround(at: here)
            }
        }
    }

    /// Typing into something no longer on screen stops.
    private func stopTypingIntoHidden() {
        switch keyboardTarget {
        case .address, .page: if !isOnGlasses(.browser) { endTyping() }
        case .mapSearch: if !mapFillsCanvas { endTyping() }
        case .mac: if !isOnGlasses(.mac) { endTyping() }
        case .note: if !isOnGlasses(.note) { endTyping() }
        case nil: break
        }
    }

    /// The map's raster is sized for its panel; going to or from the full canvas needs another
    /// one. The old one stays up, at the same zoom, until it arrives.
    private func panelsChanged() {
        stopTypingIntoHidden()
        startWidgetSources()
        if isOnGlasses(.mac) {
            desktopLink.start()
        } else {
            desktopLink.stop()
            desktopFocused = false
            if keyboardTarget == .mac { endTyping() }
        }
        if groundSpan > 0, groundPlan.span != groundSpan, let here = lastCoordinate {
            fetchGround(at: here)
        }
    }

    /// The wearer's position relative to the raster's centre, east and north in metres.
    private func applyGroundOffset() {
        guard let centre = groundCentre, let here = lastCoordinate else { return }
        snapshot.minimap.groundSpanMetres = groundSpan
        applyRoute()
        let metresPerDegree = 111_320.0
        snapshot.minimap.groundOffsetNorth = (here.latitude - centre.latitude) * metresPerDegree
        snapshot.minimap.groundOffsetEast = (here.longitude - centre.longitude) * metresPerDegree
            * cos(centre.latitude * .pi / 180)
    }

    /// East and north of the raster's centre, in metres.
    private func offset(of point: CLLocationCoordinate2D,
                        from centre: CLLocationCoordinate2D) -> CGPoint {
        let metresPerDegree = 111_320.0
        return CGPoint(x: (point.longitude - centre.longitude) * metresPerDegree
                            * cos(centre.latitude * .pi / 180),
                       y: (point.latitude - centre.latitude) * metresPerDegree)
    }

    /// The route, in the current raster's frame.
    private func applyRoute() {
        guard let tracker, let centre = groundCentre else {
            if !snapshot.minimap.route.isEmpty { snapshot.minimap.route = [] }
            return
        }
        snapshot.minimap.route = tracker.plan.points.map { offset(of: $0, from: centre) }
    }

    private func metres(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    // ------------------------------------------------------------------ browser

    private func makeTab() -> WebBrowser {
        let tab = WebBrowser()
        tab.homeHTML = { [weak self] in HomePage.html(self?.favorites ?? Favorite.defaults) }
        tab.onChange = { [weak self, weak tab] state in
            guard let self, let tab else { return }
            if tab === self.browser {
                self.browserChanged(state)
            } else {
                self.snapshot.browser.tabs = self.tabTitles
            }
        }
        tab.onOpenInNewTab = { [weak self] request in
            guard let self, let url = request.url else { return }
            self.openTab(url)
        }
        return tab
    }

    private var tabTitles: [String] {
        tabs.map { tab in
            let state = tab.state
            if state.isHome { return "New Tab" }
            return state.title.isEmpty ? (state.url.isEmpty ? "Loading" : state.url) : state.title
        }
    }

    /// A new tab, at the start page with the address field open as Safari does, or at a link.
    func openTab(_ url: URL? = nil) {
        guard tabs.count < BrowserMetrics.maxTabs else {
            if let url { browser.load(url) }
            return
        }
        if keyboardTarget != nil { endTyping() }
        tabs.append(makeTab())
        activeTab = tabs.count - 1
        if let url {
            browser.load(url)
        } else {
            browser.goHome()
            beginAddressEditing()
        }
        browserChanged(browser.state)
    }

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index), index != activeTab else { return }
        if keyboardTarget != nil { endTyping() }
        activeTab = index
        browserChanged(browser.state)
    }

    func closeTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        if keyboardTarget != nil { endTyping() }
        let closing = tabs.remove(at: index)
        closing.webView.removeFromSuperview()
        if tabs.isEmpty {
            tabs = [makeTab()]
            activeTab = 0
            browser.goHome()
        } else if index < activeTab || activeTab >= tabs.count {
            activeTab = max(activeTab - 1, 0)
        }
        browserChanged(browser.state)
    }

    private func browserChanged(_ state: WebBrowser.State) {
        var browser = snapshot.browser
        if browser.isFullscreen && !state.isFullscreen { snapshot.cursor = pointer.position }
        browser.isFullscreen = state.isFullscreen
        browser.isHome = state.isHome
        browser.isFavorite = !state.isHome && favorites.contains {
            $0.site == Favorite.site(of: state.absoluteURL)
        }
        if keyboardTarget != .address { browser.url = state.url }
        browser.title = state.title
        browser.canGoBack = state.canGoBack
        browser.canGoForward = state.canGoForward
        browser.loading = state.loading
        browser.tabs = tabTitles
        browser.activeTab = activeTab
        snapshot.browser = browser
    }

    /// Every button on the phone lands here.
    func perform(_ action: PhoneAction) {
        switch action {
        case .back: browser.back()
        case .forward: browser.forward()
        case .reload: browser.reload()
        case .home: browser.goHome()
        case .newTab: openTab()
        case let .selectTab(index): selectTab(index)
        case let .closeTab(index): closeTab(index)
        case .favorite: toggleFavorite()
        case .address:
            if mapFillsCanvas {
                keyboardTarget == .mapSearch ? endTyping() : beginMapSearch()
            } else {
                keyboardTarget == .address ? endTyping() : beginAddressEditing()
            }
        case .keyboard:
            if keyboardTarget != nil {
                endTyping()
            } else if typesOnDesktop {
                beginDesktopTyping()
            } else {
                beginPageTyping()
            }
        case let .selectWindow(index):
            let windows = snapshot.desktop.windows
            let id = index.flatMap { windows.indices.contains($0) ? windows[$0].id : nil }
            desktopLink.send(.select(window: id))
        case let .showWindows(show):
            stripShowsWindows = show
        case .settings: showingSettings = true
        case let .tapPanel(kind):
            // Fullscreen, whether a held panel or a video, and any tap ends it.
            if solo != nil {
                solo = nil
                return
            }
            if snapshot.browser.isFullscreen {
                browser.toggleFullscreen()
                return
            }
            if clearView { clearView = false }
            arrangement.toggleHidden(kind)
        case let .solo(kind):
            clearView = false
            solo = kind
        case .clearView:
            if solo != nil { solo = nil }
            clearView.toggle()
        case let .editGlasses(on):
            if on { endTyping() }
            editingGlasses = on
        case let .place(kind, spot):
            arrangement.place(kind, at: spot)
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

    private var layout: GlassesLayout {
        GlassesLayout(arrangement: arrangement, solo: solo, clearView: clearView,
                      tabCount: tabs.count, activeTab: activeTab,
                      fullscreen: snapshot.browser.isFullscreen,
                      desktopAspect: snapshot.desktop.aspect)
    }

    /// The keyboard button types on the Mac when it is the only thing to type on, or when the
    /// last click went to it.
    private var typesOnDesktop: Bool {
        guard isOnGlasses(.mac) else { return false }
        return desktopFocused || !isOnGlasses(.browser)
    }

    /// A left click wherever the cursor is. The glasses take no touches, so this is arithmetic
    /// against the layout the canvas was drawn with. The pointer's own position, not the drawn
    /// cursor, which hides itself over a fullscreen video.
    private func click() {
        if mapFillsCanvas { return mapClick() }
        switch layout.hitTest(pointer.position) {
        case .back: browser.back()
        case .forward: browser.forward()
        case .reload: browser.reload()
        case .newTab: openTab()
        case let .selectTab(index): selectTab(index)
        case let .closeTab(index): closeTab(index)
        case .address:
            desktopFocused = false
            beginAddressEditing()
        case let .mac(point):
            // Typing on the page stops; typing on the Mac carries on into what was clicked.
            if keyboardTarget != nil && keyboardTarget != .mac { endTyping() }
            desktopFocused = true
            desktopLink.send(.click(x: point.x, y: point.y, button: 0))
        case let .page(point):
            desktopFocused = false
            if keyboardTarget == .address || keyboardTarget == .mac || keyboardTarget == .note {
                endTyping()
            }
            Task {
                if await browser.click(at: point) { beginPageTyping() }
            }
        case let .widget(kind, point, size):
            widgetClick(kind, at: point, size: size)
        case .none: break
        }
    }

    /// Clicks on widgets, small or held up alone. Most only show things; these do.
    private func widgetClick(_ kind: HudPanelKind, at point: CGPoint, size: CGSize) {
        let alone = solo == kind
        switch kind {
        case .note:
            keyboardTarget == .note ? endTyping() : beginNoteEditing()
        case .captions:
            captions.toggle()
        case .music:
            switch MusicLayout.control(at: point, in: size, large: alone) {
            case .previous: music.previous()
            case .playPause: music.playPause()
            case .next: music.next()
            case nil: break
            }
        case .clock where alone:
            if ClockAppLayout.timerCard.contains(point) {
                timer.toggle(at: Date())
                timerChanged()
            }
        default:
            break
        }
    }

    /// Scrolls the page under the cursor, or the page as a whole when the cursor is elsewhere:
    /// the rail should scroll the page wherever the pointer happens to be parked.
    private func scrollPage(_ ticks: Int) {
        guard ticks != 0 else { return }
        // In the Maps app, scrolling zooms: down to see more, up to see closer.
        if mapFillsCanvas { return zoomMap(pow(1.1, Double(ticks))) }
        switch layout.hitTest(pointer.position) {
        case let .mac(p):
            // A Mac wheel's positive is up; a tick's is down the page.
            desktopLink.send(.scroll(x: p.x, y: p.y, dx: 0, dy: Double(-ticks * 48)))
            return
        case let .widget(.clock, p, _) where solo == .clock:
            // The wheel sets the timer: up for more.
            if ClockAppLayout.timerCard.contains(p) {
                timer.adjust(notches: -ticks)
                UserDefaults.standard.set(timer.setSeconds, forKey: "timerSeconds")
                timerChanged()
            }
            return
        case .widget(.note, _, _) where solo == .note:
            snapshot.note.scroll = max(snapshot.note.scroll + CGFloat(ticks) * 40, 0)
            return
        case .widget:
            return
        default:
            break
        }
        guard let content = layout.contentFrame else { return }
        let point: CGPoint
        if case let .page(p) = layout.hitTest(pointer.position) {
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

    func beginMapSearch() {
        if keyboardTarget == .address { snapshot.browser.isEditingAddress = false }
        keyboardTarget = .mapSearch
        draft = snapshot.maps.query
        snapshot.maps.isEditing = true
    }

    func beginDesktopTyping() {
        if keyboardTarget == .address { snapshot.browser.isEditingAddress = false }
        keyboardTarget = .mac
        draft = Self.sentinel
    }

    func beginNoteEditing() {
        if keyboardTarget == .address { snapshot.browser.isEditingAddress = false }
        keyboardTarget = .note
        draft = snapshot.note.text
        snapshot.note.isEditing = true
    }

    func endTyping() {
        if keyboardTarget == .mapSearch { snapshot.maps.isEditing = false }
        if keyboardTarget == .note {
            snapshot.note.isEditing = false
            UserDefaults.standard.set(snapshot.note.text, forKey: "note")
        }
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
        case .note:
            draft = new
            snapshot.note.text = new
        case .mapSearch:
            draft = new
            snapshot.maps.query = new
            // Results as you type, once the typing pauses.
            searchDebounce?.invalidate()
            searchDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                MainActor.assumeIsolated { self.runMapSearch() }
            }
        case .page, .mac:
            let sentinel = Self.sentinel
            let old = draft.hasPrefix(sentinel) ? String(draft.dropFirst()) : draft
            if new.hasPrefix(sentinel) {
                send(from: old, to: String(new.dropFirst()))
                draft = new
            } else {
                // The sentinel went: one backspace past everything typed here.
                send(from: old, to: new)
                deleteBackward(1)
                draft = sentinel + new
            }
        case nil:
            draft = new
        }
    }

    private func send(from old: String, to new: String) {
        let edit = TextEdit.between(old, new)
        deleteBackward(edit.deletes)
        guard !edit.insert.isEmpty else { return }
        if keyboardTarget == .mac {
            desktopLink.send(.text(edit.insert))
        } else {
            browser.insert(edit.insert)
        }
    }

    private func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        if keyboardTarget == .mac {
            for _ in 0..<count { desktopLink.send(.key("delete")) }
        } else {
            browser.deleteBackward(count)
        }
    }

    func submitTyping() {
        switch keyboardTarget {
        case .address:
            if let url = AddressInput.url(from: draft) { browser.load(url) }
            endTyping()
        case .page:
            browser.submit()
            endTyping()
        case .note:
            endTyping()
        case .mac:
            // Return on a Mac is a line, not the end of typing: the keyboard stays up.
            desktopLink.send(.key("return"))
            draft = Self.sentinel
        case .mapSearch:
            searchDebounce?.invalidate()
            if searchResults.isEmpty {
                runMapSearch()
            } else {
                startRoute(to: 0)
            }
            endTyping()
        case nil:
            break
        }
    }

    // ------------------------------------------------------------------ maps

    private var mapsLayout: MapsLayout {
        MapsLayout(resultCount: snapshot.maps.navigation == nil ? snapshot.maps.results.count : 0,
                   navigating: snapshot.maps.navigation != nil)
    }

    private func mapClick() {
        switch mapsLayout.hitTest(pointer.position) {
        case .search: keyboardTarget == .mapSearch ? endTyping() : beginMapSearch()
        case let .result(index): startRoute(to: index)
        case .endRoute: endRoute()
        case .transport:
            snapshot.maps.driving.toggle()
            if let destination = routeDestination { route(to: destination) }
        case .zoomIn: zoomMap(1 / 1.6)
        case .zoomOut: zoomMap(1.6)
        case .none: if keyboardTarget == .mapSearch { endTyping() }
        }
    }

    /// The zoom changes at once, by stretching the raster already there; a sharp one for the new
    /// zoom follows when the zooming stops.
    private func zoomMap(_ factor: Double) {
        let next = min(max(Int((Double(mapSpan) * factor).rounded()), 120), 8000)
        guard next != mapSpan else { return }
        mapSpan = next
        snapshot.minimap.spanMetres = next
        UserDefaults.standard.set(next, forKey: "mapSpan")
        zoomRefetch?.invalidate()
        zoomRefetch = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            MainActor.assumeIsolated { self.panelsChanged() }
        }
    }

    private func runMapSearch() {
        let query = snapshot.maps.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            snapshot.maps.results = []
            snapshot.maps.status = nil
            return
        }
        guard let here = lastCoordinate else {
            snapshot.maps.status = "WAITING FOR LOCATION"
            return
        }
        snapshot.maps.status = "SEARCHING"
        Task {
            let found = (try? await mapsService.search(query, near: here)) ?? []
            // A newer search has started since; its answer is the one that counts.
            guard snapshot.maps.query.trimmingCharacters(in: .whitespaces) == query else { return }
            searchResults = found
            snapshot.maps.results = found.map(\.place)
            snapshot.maps.status = found.isEmpty ? "NO RESULTS" : nil
        }
    }

    private func startRoute(to index: Int) {
        guard searchResults.indices.contains(index) else { return }
        if keyboardTarget == .mapSearch { endTyping() }
        route(to: searchResults[index])
    }

    private func route(to destination: MapsService.Result) {
        guard let here = lastCoordinate else { return }
        routeDestination = destination
        snapshot.maps.status = "FINDING A ROUTE"
        let driving = snapshot.maps.driving
        Task {
            do {
                let plan = try await mapsService.route(from: here, to: destination.item,
                                                       driving: driving)
                var tracker = NavigationTracker(plan: plan)
                snapshot.maps.navigation = tracker.update(at: lastCoordinate ?? here)
                self.tracker = tracker
                snapshot.maps.results = []
                snapshot.maps.query = ""
                snapshot.maps.status = nil
                searchResults = []
                applyRoute()
            } catch {
                snapshot.maps.status = "NO ROUTE"
            }
        }
    }

    private func endRoute() {
        tracker = nil
        routeDestination = nil
        snapshot.maps.navigation = nil
        applyRoute()
    }

    // ------------------------------------------------------------------ widgets

    /// Starts the sources of whatever is on the glasses (or arranged there), once each.
    private func startWidgetSources() {
        let placed = { (kind: HudPanelKind) in self.arrangement.isPlaced(kind) || self.solo == kind }
        if placed(.music) { music.start() }
        if placed(.activity) { activityProvider.start() }
        if placed(.sky) || solo == .sky { updateSky(force: true) }
        // Hidden or cleared away, captions keep listening (the phone shows a red dot); taken
        // off the glasses, they stop.
        if captions.state.isListening && !placed(.captions) { captions.stop() }
    }

    /// Every second, with the clock.
    private func tickWidgets() {
        let now = Date()
        if timer.isRunning || snapshot.timer.state == .done { timerChanged(now: now) }
        music.tick()
        activityProvider.tick(now: now)
        captions.tick(now: now)
        updateSky()
    }

    private func timerChanged(now: Date = Date()) {
        let reading = timer.reading(at: now)
        if reading.state == .done, snapshot.timer.state != .done {
            timerDoneAt = now
            buzz()
        }
        // Done for a while: back to ready, at the same time.
        if reading.state == .done, let doneAt = timerDoneAt, now.timeIntervalSince(doneAt) > 12 {
            timer.reset()
            timerDoneAt = nil
            snapshot.timer = timer.reading(at: now)
            return
        }
        if reading != snapshot.timer { snapshot.timer = reading }
    }

    /// The phone is in the hand: three firm taps say the time is up.
    private func buzz() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        for delay in [0.45, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                generator.notificationOccurred(.warning)
            }
        }
    }

    /// The sky moves slowly: once a minute is plenty, and the stars only while they are seen.
    private func updateSky(force: Bool = false) {
        guard arrangement.isPlaced(.sky) || solo == .sky,
              force || Date().timeIntervalSince(lastSky) > 60,
              let here = lastCoordinate else { return }
        lastSky = Date()
        let latitude = here.latitude, longitude = here.longitude
        Task.detached(priority: .utility) {
            let sky = SkyModel.compute(at: Date(), latitude: latitude, longitude: longitude)
            await MainActor.run { self.snapshot.sky = sky }
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
        case .move:
            momentum.stop()
            pointerMoved()
        case .tapClick: click()
        case .rightClick:
            switch layout.hitTest(pointer.position) {
            case let .mac(p):
                desktopFocused = true
                desktopLink.send(.click(x: p.x, y: p.y, button: 1))
            case let .widget(.clock, p, _) where solo == .clock && ClockAppLayout.timerCard.contains(p):
                timer.reset()
                timerChanged()
            default:
                break
            }
        case .doubleTapDragStart:
            if case let .mac(p) = layout.hitTest(pointer.position) {
                desktopDragging = true
                desktopLink.send(.press(x: p.x, y: p.y))
            }
        case .dragEnd:
            if desktopDragging {
                desktopDragging = false
                let p = desktopPoint(clamped: pointer.position)
                desktopLink.send(.release(x: p.x, y: p.y))
            }
        default: break
        }

        scrollPage(pointer.drainScroll())
        snapshot.cursor = pointer.position
        scheduleCursorHide()
    }

    /// Mouse movement reaches the page, a few dozen times a second rather than on every
    /// sample: enough for hover menus and for video controls to wake, without flooding WebKit.
    private func pointerMoved() {
        if isOnGlasses(.mac), Date().timeIntervalSince(lastDesktopMove) > 0.033 {
            if desktopDragging {
                // A drag keeps going past the picture's edge, pinned to it.
                let p = desktopPoint(clamped: pointer.position)
                lastDesktopMove = Date()
                desktopLink.send(.move(x: p.x, y: p.y))
                return
            }
            if case let .mac(p) = layout.hitTest(pointer.position) {
                lastDesktopMove = Date()
                desktopLink.send(.move(x: p.x, y: p.y))
                return
            }
        }
        guard Date().timeIntervalSince(lastHover) > 0.05,
              case let .page(point) = layout.hitTest(pointer.position) else { return }
        lastHover = Date()
        browser.hover(at: point)
    }

    /// Over a fullscreen video the cursor gets out of the way once it stops, as it does on a
    /// desktop. Anywhere else it stays: it is the only way to know where a click will land.
    private func scheduleCursorHide() {
        cursorHideTimer?.invalidate()
        guard snapshot.browser.isFullscreen else { return }
        cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.snapshot.browser.isFullscreen else { return }
                self.snapshot.cursor = nil
            }
        }
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

    func cornerTapped() { handle(.rightClick) }

    /// A canvas point as a fraction of the Mac's picture, held to its edges.
    private func desktopPoint(clamped point: CGPoint) -> CGPoint {
        guard let picture = layout.desktopPicture else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(max((point.x - picture.minX) / picture.width, 0), 1),
                       y: min(max((point.y - picture.minY) / picture.height, 0), 1))
    }
}
