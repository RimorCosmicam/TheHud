import SwiftUI
import Combine
import CoreLocation
import AVFoundation
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
    /// What is on the glasses and where, as arranged on the phone: the current scene's.
    @Published private(set) var arrangement: HudArrangement {
        didSet {
            guard arrangement != oldValue else { return }
            scenes[sceneIndex].arrangement = arrangement
            saveScenes()
            panelsChanged()
            if padApp(in: oldValue) != padApp {
                appPadSetAside = false
                padChanged()
            }
        }
    }
    /// Three arrangements to switch between, each keeping its own edits. Saved.
    private(set) var scenes: [HudScene]
    @Published private(set) var sceneIndex: Int
    /// One panel held up on its own, filling the glasses. Not saved: it is a moment's focus,
    /// and the arrangement is what comes back.
    @Published private(set) var solo: HudPanelKind? {
        didSet {
            guard solo != oldValue else { return }
            appPadSetAside = false
            panelsChanged()
            padChanged()
        }
    }
    /// Everything hidden, to see straight through the glasses.
    @Published private(set) var clearView = false {
        didSet {
            guard clearView != oldValue else { return }
            panelsChanged()
            padChanged()
        }
    }

    /// TOUCHPAD or REMOTE, as last picked. Saved.
    @Published private(set) var pointerMode: PointerMode =
        PointerMode(rawValue: UserDefaults.standard.string(forKey: "pointerMode") ?? "") ?? .touchpad
    /// The fullscreen app's own controls were swapped for the pointer, until the app changes.
    @Published private(set) var appPadSetAside = false
    /// The app whose controls the pad can show: the fullscreen one, or else the centre's.
    var padApp: HudPanelKind? {
        if let remoteState {
            return Self.padApp(remoteState.arrangement, solo: remoteState.solo, clearView: remoteState.clearView)
        }
        return padApp(in: arrangement)
    }

    private func padApp(in arrangement: HudArrangement) -> HudPanelKind? {
        Self.padApp(arrangement, solo: solo, clearView: clearView)
    }

    private static func padApp(_ arrangement: HudArrangement, solo: HudPanelKind?, clearView: Bool) -> HudPanelKind? {
        if clearView { return nil }
        if let solo { return solo.hasPhoneControls ? solo : nil }
        guard let centre = arrangement.centre?.kind, centre.hasPhoneControls,
              arrangement.isShown(centre) else { return nil }
        return centre
    }

    /// What the phone's lower half is right now.
    var pad: PhonePad {
        if padApp != nil, !appPadSetAside { return .app }
        return pointerMode == .touchpad ? .touchpad : .remote
    }
    @Published var showingCaptionSessions = false

    // ------------------------------------------------------------------ Remote Connect

    /// The Android phone, while this one works its glasses.
    let remoteLink = RemoteLink()
    @Published var showingRemoteConnect = false
    @Published private(set) var remoteStatus: RemoteLink.Status = .off
    /// Remote Connect's mode, picked when pairing: HOST runs this phone's apps on the Android
    /// phone's glasses; otherwise this phone is the Android phone's remote. Saved.
    @Published private(set) var remoteHosting = UserDefaults.standard.bool(forKey: "remoteHosting")
    private var hostStreamer: HostStreamer?
    /// Host mode: YouTube's sound from this phone (for headphones) instead of the glasses. Saved.
    /// The app's colour: the accent everywhere, the touchpad, the icon, and the Android phone's
    /// glasses while connected. Saved.
    @Published var themeColor: ThemeColor = ThemeColor(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .mustard {
        didSet {
            guard themeColor != oldValue else { return }
            UserDefaults.standard.set(themeColor.rawValue, forKey: "theme")
            themeChanged()
        }
    }

    @Published var hostSoundHere = UserDefaults.standard.bool(forKey: "hostSoundHere") {
        didSet {
            UserDefaults.standard.set(hostSoundHere, forKey: "hostSoundHere")
            hostSoundChanged()
        }
    }
    /// The Android phone's player as it last said, and when.
    private var androidVideo: (id: String, time: Double, playing: Bool, at: Date)?
    /// Back from the lock, the Android phone's video leads a moment longer while this one catches up.
    private var hostHoldUntil = Date.distantPast
    /// The Android phone's state, while connected. Everything the phone's screen draws comes
    /// from here then, and its buttons go there; this phone's own scenes are left alone.
    @Published private(set) var remoteState: RemoteState?
    /// The keyboard's text while typing on the Android phone. Taken from it only when its
    /// keyboard comes up, so what is typed here is never overwritten by its own echo.
    @Published private(set) var remoteDraft = ""
    var isRemote: Bool { remoteState != nil }

    var shownArrangement: HudArrangement { remoteState?.arrangement ?? arrangement }
    var shownSolo: HudPanelKind? { remoteState.map(\.solo) ?? solo }
    var shownClearView: Bool { remoteState?.clearView ?? clearView }
    var shownSnapshot: HudSnapshot { remoteState?.applied(to: snapshot) ?? snapshot }
    var shownScenes: [String] { remoteState?.scenes ?? scenes.map(\.name) }
    var shownSceneIndex: Int { remoteState?.scene ?? sceneIndex }
    var shownGlassesConnected: Bool { remoteState?.glassesConnected ?? glassesConnected }
    var shownKeyboardTarget: KeyboardTarget? {
        guard let remoteState else { return keyboardTarget }
        return remoteState.keyboard.flatMap(KeyboardTarget.init(name:))
    }
    var shownDraft: String { isRemote ? remoteDraft : draft }
    /// Pointing the phone, for REMOTE.
    let remote = RemoteMotion()
    private var remoteTouches: [RemoteZone: TouchPoint] = [:]
    /// Zones whose touch only woke the cursor, so letting go of them does nothing either.
    private var remoteWakers: Set<RemoteZone> = []
    private var remoteDragTimer: Timer?
    private var remoteDragging = false
    private let remoteRail = ScrollRail()
    /// Aircraft and the space station, for the sky app.
    private let overheadProvider = OverheadProvider()
    /// The phone's GLASSES section is being arranged.
    @Published private(set) var editingGlasses = false

    /// Whether a panel is on the glasses right now.
    func isOnGlasses(_ kind: HudPanelKind) -> Bool {
        if clearView { return false }
        return solo.map { $0 == kind } ?? arrangement.isShown(kind)
    }
    /// The map held up alone: it gets the whole canvas, as the Maps app.
    private var mapFillsCanvas: Bool { solo == .map && !clearView }
    /// The map as the centre's app: bigger than a slot, so it takes the canvas's raster too.
    private var mapInCentre: Bool {
        solo == nil && !clearView && arrangement.centre?.kind == .map && arrangement.isShown(.map)
    }
    @Published var config: HalftoneConfig = .miniMateDefault
    @Published var trackpad = TouchpadSettings()

    /// While the glasses are on, the phone does not auto-lock; and when it is locked anyway, to
    /// go in a pocket, location keeps the app running so the glasses keep being drawn.
    @Published var glassesConnected = false {
        didSet {
            UIApplication.shared.isIdleTimerDisabled = glassesConnected
            location.keepsRunningInBackground = glassesConnected
            updateCamera()
        }
    }

    /// The language the captions listen for.
    @Published var captionsLanguage: String = UserDefaults.standard.string(forKey: "captionsLanguage")
        ?? CaptionsEngine.defaultLanguage {
        didSet {
            UserDefaults.standard.set(captionsLanguage, forKey: "captionsLanguage")
            captions.language = captionsLanguage
        }
    }

    @Published private(set) var favorites: [Favorite]
    @Published var showingSettings = false
    @Published private(set) var railActive = false
    @Published var cornerPressed = false

    /// Where keystrokes go while the keyboard is up.
    enum KeyboardTarget: String { case address, page, mapSearch, mac, note, youtubeSearch
        /// As the Android app names them.
        init?(name: String) { self.init(rawValue: name) }
    }
    @Published private(set) var keyboardTarget: KeyboardTarget?
    /// The invisible text field's contents. For the address bar it is the draft itself; for the
    /// page it is a proxy that is diffed into insertions and deletions.
    @Published private(set) var draft = ""

    /// One web view per tab, so each keeps its page, scroll position and history.
    private(set) var tabs: [WebBrowser] = []
    @Published private(set) var activeTab = 0
    var browser: WebBrowser { tabs[activeTab] }

    private var cursorHideTimer: Timer?
    /// Put away for idleness or a lock; the next touch wakes it without clicking.
    private var cursorAsleep = false
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
    /// YouTube's player, a web view of its own on the browser's sign-in.
    let youtubePlayer = YouTubePlayer()
    /// Off unless asked for: the Subscriptions list.
    @Published var youtubeSubscriptions = UserDefaults.standard.bool(forKey: "youtubeSubscriptions") {
        didSet {
            UserDefaults.standard.set(youtubeSubscriptions, forKey: "youtubeSubscriptions")
            snapshot.youtube.showsSubscriptions = youtubeSubscriptions
            if youtubeSubscriptions {
                loadYouTube(.subscriptions)
            } else if snapshot.youtube.tab == .subscriptions {
                snapshot.youtube.tab = .home
            }
        }
    }
    private var youtubeLoaded: [HudSnapshot.YouTube.Tab: Date] = [:]
    private var youtubeSearchDebounce: Timer?
    /// Scroll ticks not yet a whole row, or a whole five seconds.
    private var youtubeScroll = 0
    /// The Music app's artwork for what is playing.
    @Published private(set) var artwork: Image?
    /// The photo library's pictures on show, by index.
    @Published private(set) var photoImages: [Int: Image] = [:]
    private let photosProvider = PhotosProvider()
    /// The phone's camera, while it is on the glasses and the phone's screen is this app's.
    let camera = CameraService()
    /// The phone's own screen is this app's: the camera is only given to the app in front.
    private var phoneActive = UIApplication.shared.applicationState == .active
    private var photoScroll = 0
    private var lastSlide = Date()
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
        let (scenes, index) = Self.loadScenes()
        self.scenes = scenes
        sceneIndex = index
        arrangement = scenes[index].arrangement
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
        snapshot.skyView = Self.loadSkyView()
        loadSettings()

        tabs = [makeTab()]
    }

    private static let scenesKey = "scenes"
    private static let sceneIndexKey = "scene"

    /// The saved scenes. From before there were scenes, the presets, with what was arranged
    /// then kept as the first.
    private static func loadScenes() -> ([HudScene], Int) {
        let defaults = UserDefaults.standard
        let index = min(max(defaults.integer(forKey: sceneIndexKey), 0), HudScene.count - 1)
        if let data = defaults.data(forKey: scenesKey),
           var stored = try? JSONDecoder().decode([HudScene].self, from: data),
           stored.count == HudScene.count {
            // The Apps Center: one app in the centre and new apps beside it. The scenes start
            // again from the new presets, once.
            if defaults.integer(forKey: "scenesVersion") < 3 {
                stored = HudScene.presets
                defaults.set(3, forKey: "scenesVersion")
                if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: scenesKey) }
            }
            return (stored, index)
        }
        defaults.set(3, forKey: "scenesVersion")
        var scenes = HudScene.presets
        if let data = defaults.data(forKey: "arrangement"),
           let old = try? JSONDecoder().decode(HudArrangement.self, from: data) {
            scenes[0].arrangement = old
        } else if let old = defaults.stringArray(forKey: "visiblePanels") {
            let kinds = old.compactMap { HudPanelKind(rawValue: $0 == "desktop" ? "mac" : $0) }
            scenes[0].arrangement = HudArrangement(visible: Set(kinds))
        }
        return (scenes, 0)
    }

    private func saveScenes() {
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: Self.scenesKey)
        }
        UserDefaults.standard.set(sceneIndex, forKey: Self.sceneIndexKey)
    }

    private func switchScene(to index: Int) {
        guard HudScene.presets.indices.contains(index) else { return }
        solo = nil
        clearView = false
        sceneIndex = index
        saveScenes()
        arrangement = scenes[index].arrangement
    }

    private func resetScene(_ index: Int) {
        guard HudScene.presets.indices.contains(index) else { return }
        scenes[index] = HudScene.presets[index]
        if index == sceneIndex {
            arrangement = scenes[index].arrangement
        }
        saveScenes()
        switchScene(to: index)
    }
    private static let favoritesKey = "favorites"

    /// Called once the phone scene is on screen.
    func start() {
        captions.language = captionsLanguage
        startRemoteConnect()
        // Locked, the phone is in a pocket: nothing to point at. With the glasses plugged in
        // the app never goes to the background (their scene stays on), so it is the phone's
        // own scene that is watched, and the lock itself where a passcode makes it known.
        let center = NotificationCenter.default
        for name in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard (note.object as? UIScene)?.session.role == .windowApplication else { return }
                    self?.phoneWentAway()
                }
            }
        }
        for name in [UIApplication.protectedDataWillBecomeUnavailableNotification,
                     UIApplication.didEnterBackgroundNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.phoneWentAway() }
            }
        }
        // Host mode: locked, nothing here can be filmed, so the Android phone takes over the glasses
        // until this phone is back.
        for name in [UIApplication.didEnterBackgroundNotification,
                     UIApplication.protectedDataWillBecomeUnavailableNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hostStandIn(true) }
            }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hostStandIn(false) }
        }
        center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard (note.object as? UIScene)?.session.role == .windowApplication else { return }
                self?.phoneCameBack()
            }
        }
        scheduleCursorHide()
        remote.onMove = { [weak self] dx, dy, deliberate in self?.remoteMoved(dx, dy, deliberate) }
        padChanged()
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
        photosProvider.onChange = { [weak self] in self?.photosChanged() }
        camera.onChange = { [weak self] in self?.cameraChanged() }
        snapshot.youtube.showsSubscriptions = youtubeSubscriptions
        youtubePlayer.onChange = { [weak self] state in self?.youtubeChanged(state) }
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
            snapshot.agenda = calendar.agendaApp()
        } else {
            // The now line and "IN 25 MIN" move with the minute.
            let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if minute != snapshot.agenda.nowMinute { lastCalendarRead = .distantPast }
        }
        clock.nextEvent = calendarNext?.title
        clock.nextEventTime = calendarNext?.time
        clock.agenda = calendarAgenda
        // A redraw a second is for the clock app alone.
        tickWidgets()
        let clockApp = solo == .clock || solo == nil && arrangement.centre?.kind == .clock
        guard isOnGlasses(.clock) && clockApp || calendarChanged
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
        if mapFillsCanvas || mapInCentre {
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
        // The teleprompter reads the note, so writing it there is writing the note.
        case .note: if !isOnGlasses(.note) && !isOnGlasses(.prompter) { endTyping() }
        case .youtubeSearch: if !isOnGlasses(.youtube) { endTyping() }
        case nil: break
        }
    }

    /// The map's raster is sized for its panel; going to or from the full canvas needs another
    /// one. The old one stays up, at the same zoom, until it arrives.
    private func panelsChanged() {
        stopTypingIntoHidden()
        startWidgetSources()
        updateCamera()
        if isOnGlasses(.mac) && !hostStandingIn {
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
        if browser.isFullscreen && !state.isFullscreen, !cursorAsleep {
            snapshot.cursor = pointer.position
            scheduleCursorHide()
        }
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
        // Working the Android phone: what its glasses do goes there; this phone's own settings,
        // pads and editor stay here.
        if isRemote, let message = RemoteWire.message(for: action) {
            remoteLink.send(message)
            return
        }
        switch action {
        case .remoteConnect: showingRemoteConnect = true
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
        case let .centre(kind):
            clearView = false
            solo = nil
            arrangement.setCentre(kind)
        case let .prompter(action):
            prompterAction(action)
        case let .photos(action):
            photosAction(action)
        case let .camera(action):
            camera.perform(action)
        case .clearView:
            if solo != nil { solo = nil }
            clearView.toggle()
        case let .editGlasses(on):
            if on { endTyping() }
            editingGlasses = on
        case let .place(kind, spot):
            arrangement.place(kind, at: spot)
        case let .scene(index):
            switchScene(to: index)
        case let .resetScene(index):
            resetScene(index)
        case let .layout(edge):
            arrangement.setStrip(edge)
        case let .pad(choice):
            switch choice {
            case .app:
                appPadSetAside = false
            case .touchpad, .remote:
                if padApp != nil { appPadSetAside = true }
                pointerMode = choice == .touchpad ? .touchpad : .remote
                UserDefaults.standard.set(pointerMode.rawValue, forKey: "pointerMode")
            }
            padChanged()
        case let .remote(zone, phase, point):
            remoteTouch(zone, phase, point)
        case let .sky(action):
            skyAction(action)
        case let .music(control):
            switch control {
            case .previous: music.previous()
            case .playPause: music.playPause()
            case .next: music.next()
            }
        case let .timer(action):
            switch action {
            case .toggle: timer.toggle(at: Date())
            case .reset: timer.reset()
            case let .set(minutes): timer.set(minutes: minutes)
            case let .add(minutes): timer.add(minutes: minutes)
            }
            UserDefaults.standard.set(timer.setSeconds, forKey: "timerSeconds")
            timerChanged()
        case .captionsToggle:
            captions.toggle()
        case .captionsSessions:
            showingCaptionSessions = true
        case let .captionsLanguage(id):
            captionsLanguage = id
        case let .youtube(action):
            youtubeAction(action)
        case let .note(action):
            switch action {
            case .write:
                keyboardTarget == .note ? endTyping() : beginNoteEditing()
            case .clear:
                snapshot.note.text = ""
                snapshot.note.scroll = 0
                if keyboardTarget == .note { draft = "" }
                UserDefaults.standard.set("", forKey: "note")
            case let .scroll(dy):
                snapshot.note.scroll = dy.isFinite ? max(snapshot.note.scroll + dy, 0) : 0
            }
        }
    }

    // ------------------------------------------------------------------ the phone's pads

    /// The pad changed: the gyro runs only for REMOTE, and an app with its own controls needs
    /// no cursor over it.
    private func padChanged() {
        let pad = self.pad
        if pad == .remote, UIApplication.shared.applicationState != .background {
            remote.start()
        } else {
            remote.stop()
        }
        remoteTouches.removeAll()
        remoteWakers.removeAll()
        contacts = []
        remoteDragTimer?.invalidate()
        if remoteDragging {
            remoteDragging = false
            handle(.dragEnd)
        }
        if pad == .app { putCursorAway() }
    }

    private func remoteMoved(_ dx: Int, _ dy: Int, _ deliberate: Bool) {
        // Put away, the cursor waits for a thumb: a phone swinging in a hand or a pocket
        // should not bring it back.
        guard isRemote || !cursorAsleep, pad == .remote else { return }
        if isRemote {
            remoteLink.send(RemoteWire.message(for: GestureEvent.move(dx: dx, dy: dy, isDragging: remoteDragging)))
            return
        }
        pointer.apply(.move(dx: dx, dy: dy, isDragging: remoteDragging))
        pointerMoved()
        snapshot.cursor = pointer.position
        if deliberate { scheduleCursorHide() }
    }

    private func remoteTouch(_ zone: RemoteZone, _ phase: RemoteTouchPhase, _ point: CGPoint) {
        // The halftone ripples under the thumb, as it does on the trackpad.
        switch phase {
        case .began: remoteTouches[zone] = TouchPoint(x: point.x, y: point.y, id: 900 + zone.rawValue)
        case .moved:
            remoteTouches[zone]?.x = point.x
            remoteTouches[zone]?.y = point.y
        case .ended: remoteTouches[zone] = nil
        }
        contacts = Array(remoteTouches.values)

        if cursorAsleep, phase == .began, !isRemote {
            cursorAsleep = false
            snapshot.cursor = pointer.position
            remoteWakers.insert(zone)
            scheduleCursorHide()
            return
        }
        if remoteWakers.contains(zone) {
            if phase == .ended { remoteWakers.remove(zone) }
            return
        }

        switch (zone, phase) {
        case (.click, .began):
            // Pressing shakes the phone: the cursor holds still so the click lands where aimed.
            remote.hold(for: 0.18)
            remoteDragTimer?.invalidate()
            remoteDragTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.remoteDragging = true
                    self.remote.release()
                    self.handle(.doubleTapDragStart)
                }
            }
        case (.click, .ended):
            remoteDragTimer?.invalidate()
            if remoteDragging {
                remoteDragging = false
                handle(.dragEnd)
            } else {
                handle(.tapClick)
            }
        case (.rightClick, .began):
            remote.hold(for: 0.18)
        case (.rightClick, .ended):
            handle(.rightClick)
        case (.scroll, .began):
            // Still while scrolling: the page moves, not the cursor.
            remote.hold(for: 600)
            momentum.stop()
            remoteRail.scrollSpeed = trackpad.scrollSpeed
            remoteRail.naturalScrolling = trackpad.naturalScrolling
            remoteRail.begin(at: point.y)
        case (.scroll, .moved):
            if let ticks = remoteRail.move(to: point.y) {
                pointer.apply(.scroll(v: ticks, h: 0))
                scrollPage(pointer.drainScroll())
            }
        case (.scroll, .ended):
            remoteRail.end()
            remote.release()
        case (.centre, .ended) where isRemote:
            remoteLink.send(RemoteWire.centreCursor())
        case (.centre, .ended):
            pointer.place(at: CGPoint(x: HudTheme.glassesSize.width / 2, y: HudTheme.glassesSize.height / 2))
            snapshot.cursor = pointer.position
            pointerMoved()
        default:
            break
        }
        scheduleCursorHide()
    }

    // ------------------------------------------------------------------ sky

    private func skyAction(_ action: SkyAction) {
        switch action {
        case let .look(pan, tilt): snapshot.skyView.look(pan: pan, tilt: tilt)
        case let .zoom(factor): snapshot.skyView.zoom(by: factor)
        case .recentre: snapshot.skyView.recentre()
        case let .toggle(layer):
            snapshot.skyView.toggle(layer)
            if let selected = snapshot.skyView.selected, !selected.hasPrefix("body:"), !selected.hasPrefix("star:") {
                snapshot.skyView.selected = nil
            }
            updateOverhead(force: true)
        case let .select(id): snapshot.skyView.selected = id
        }
        saveSkyView()
    }

    private static func loadSkyView() -> SkyView {
        let defaults = UserDefaults.standard
        var view = SkyView()
        if let layers = defaults.stringArray(forKey: "skyLayers") {
            view.layers = Set(layers.compactMap(SkyLayer.init(rawValue:)))
        }
        if let fov = defaults.object(forKey: "skyFOV") as? Double { view.zoom(by: fov / view.fov) }
        return view
    }

    private func saveSkyView() {
        let defaults = UserDefaults.standard
        defaults.set(snapshot.skyView.layers.map(\.rawValue).sorted(), forKey: "skyLayers")
        defaults.set(snapshot.skyView.fov, forKey: "skyFOV")
    }

    /// Planes and the station, while the sky fills the glasses: fetched every so often, moved
    /// along their tracks every second in between.
    private func updateOverhead(force: Bool = false, now: Date = Date()) {
        guard solo == .sky, !clearView, let here = lastCoordinate else { return }
        let layers = snapshot.skyView.layers
        overheadProvider.refresh(latitude: here.latitude, longitude: here.longitude,
                                 planes: layers.contains(.planes), station: layers.contains(.iss), now: now)
        snapshot.overhead = overheadProvider.overhead(latitude: here.latitude, longitude: here.longitude, now: now)
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
            appClick(kind, at: point, size: size, large: solo == kind)
        case let .centre(kind, point, size):
            appClick(kind, at: point, size: size, large: true)
        case .none: break
        }
    }

    /// Clicks on apps: as widgets, in the centre, or held up alone (`large` for the last two).
    /// Most only show things; these do.
    private func appClick(_ kind: HudPanelKind, at point: CGPoint, size: CGSize, large: Bool) {
        let alone = large
        switch kind {
        case .note:
            keyboardTarget == .note ? endTyping() : beginNoteEditing()
        case .captions:
            captions.toggle()
        case .music:
            switch MusicLayout.control(at: point, in: size, large: large) {
            case .previous: music.previous()
            case .playPause: music.playPause()
            case .next: music.next()
            case nil: break
            }
        case .youtube:
            youtubeClick(at: point, size: size, alone: alone)
        case .clock where alone:
            if ClockAppLayout.timerCard(in: size).contains(point) {
                timer.toggle(at: Date())
                timerChanged()
            }
        case .prompter:
            prompterAction(.toggle)
        case .photos where solo == .photos:
            // The gallery: a click picks a photo, and on the picked one opens it; open, a
            // click goes back to the grid.
            if snapshot.photos.viewing {
                snapshot.photos.viewing = false
            } else if let index = PhotosLayout.photo(at: point, in: size, snapshot.photos) {
                if index == snapshot.photos.selected { snapshot.photos.viewing = true }
                snapshot.photos.selected = index
            }
            photosChanged()
        case .photos:
            photosAction(.step(1))
        case .camera:
            camera.perform(.shutter)
        default:
            break
        }
    }

    /// Scrolls the page under the cursor, or the page as a whole when the cursor is elsewhere:
    /// the rail should scroll the page wherever the pointer happens to be parked.
    private func scrollPage(_ ticks: Int) {
        guard ticks != 0 else { return }
        if isRemote {
            remoteLink.send(RemoteWire.message(for: GestureEvent.scroll(v: ticks, h: 0)))
            return
        }
        // In the Maps app, scrolling zooms: down to see more, up to see closer.
        if mapFillsCanvas { return zoomMap(pow(1.1, Double(ticks))) }
        if solo == .sky && !clearView {
            snapshot.skyView.zoom(notches: ticks)
            saveSkyView()
            return
        }
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
        case let .widget(.youtube, p, size):
            youtubeScrolled(ticks, at: p, size: size, alone: solo == .youtube)
            return
        case .widget(.photos, _, _) where solo == .photos:
            photosScrolled(ticks)
            return
        case .widget(.prompter, _, _) where solo == .prompter:
            prompterNudge(ticks)
            return
        case let .centre(kind, p, size):
            centreScrolled(kind, ticks, at: p, size: size)
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

    /// The wheel over the app in the centre.
    private func centreScrolled(_ kind: HudPanelKind, _ ticks: Int, at point: CGPoint, size: CGSize) {
        switch kind {
        case .clock:
            guard ClockAppLayout.timerCard(in: size).contains(point) else { return }
            timer.adjust(notches: -ticks)
            UserDefaults.standard.set(timer.setSeconds, forKey: "timerSeconds")
            timerChanged()
        case .youtube:
            youtubeScrolled(ticks, at: point, size: size, alone: true)
        case .note:
            snapshot.note.scroll = max(snapshot.note.scroll + CGFloat(ticks) * 40, 0)
        case .photos:
            photoScroll += ticks
            let notches = photoScroll / 3
            guard notches != 0 else { return }
            photoScroll -= notches * 3
            photosAction(.step(notches))
        case .prompter:
            prompterNudge(ticks)
        case .sky:
            snapshot.skyView.zoom(notches: ticks)
            saveSkyView()
        case .map:
            zoomMap(pow(1.1, Double(ticks)))
        default:
            break
        }
    }

    // ------------------------------------------------------------------ teleprompter

    /// Every change starts again from where it is now, so the glasses' smooth scrolling never
    /// jumps.
    private func prompterAction(_ action: PrompterAction) {
        let now = Date()
        var prompter = snapshot.prompter
        prompter.anchorOffset = prompter.offset(at: now)
        prompter.anchorTime = now
        let speeds = HudSnapshot.Prompter.speeds
        switch action {
        case .toggle: prompter.isRunning.toggle()
        case .faster: prompter.speed = min(prompter.speed + 30, speeds.upperBound)
        case .slower: prompter.speed = max(prompter.speed - 30, speeds.lowerBound)
        case .restart: prompter.anchorOffset = 0
        }
        snapshot.prompter = prompter
    }

    /// The wheel moves the words by hand, running or not.
    private func prompterNudge(_ ticks: Int) {
        let now = Date()
        snapshot.prompter.anchorOffset = max(snapshot.prompter.offset(at: now) + CGFloat(ticks) * 24, 0)
        snapshot.prompter.anchorTime = now
    }

    // ------------------------------------------------------------------ camera

    /// The camera runs while it is on glasses this phone draws (its own, or the Android phone's
    /// in Host mode) and the phone's screen is this app's; the glasses say it is paused otherwise.
    private func updateCamera() {
        camera.filmsFrames = hostStreamer != nil
        camera.run(!isRemote && glassesConnected && isOnGlasses(.camera) && phoneActive && !hostStandingIn)
    }

    private func cameraChanged() {
        if snapshot.camera != camera.state { snapshot.camera = camera.state }
    }

    // ------------------------------------------------------------------ photos

    /// The library's count and the caption, and the pictures on show loaded: the gallery's page
    /// held up alone, otherwise the one photo.
    private func photosChanged() {
        var photos = snapshot.photos
        photos.hasAccess = photosProvider.hasAccess
        photos.count = photosProvider.count
        let last = max(photos.count - 1, 0)
        photos.current = min(photos.current, last)
        photos.selected = min(photos.selected, last)
        photos.scrollRow = min(photos.scrollRow, PhotosLayout.maxRow(photos.count))
        let gallery = solo == .photos && !clearView
        photos.caption = photosProvider.caption(gallery ? photos.selected : photos.current)
        if photos != snapshot.photos { snapshot.photos = photos }
        guard isOnGlasses(.photos) else {
            photosProvider.show(thumbnails: [], large: nil)
            if !photoImages.isEmpty { photoImages = [:] }
            return
        }
        let perPage = PhotosLayout.columns * PhotosLayout.rows
        let first = photos.scrollRow * PhotosLayout.columns
        let page = gallery ? Array(first..<min(first + perPage, photos.count)) : []
        photosProvider.show(thumbnails: page,
                            large: gallery ? (photos.viewing ? photos.selected : nil) : photos.current)
        photoImages = photosProvider.images
    }

    private func photosAction(_ action: PhotosAction) {
        let count = snapshot.photos.count
        guard count > 0 else { return }
        switch action {
        case let .step(by):
            if solo == .photos {
                let selected = min(max(snapshot.photos.selected + by, 0), count - 1)
                snapshot.photos.selected = selected
                snapshot.photos.scrollRow = PhotosLayout.row(showing: selected, from: snapshot.photos.scrollRow)
            } else {
                snapshot.photos.current = ((snapshot.photos.current + by) % count + count) % count
                lastSlide = Date()
            }
        case .open:
            guard solo == .photos else { return }
            snapshot.photos.viewing.toggle()
        }
        photosChanged()
    }

    /// The gallery's wheel: a row at a time, or open, photo to photo.
    private func photosScrolled(_ ticks: Int) {
        photoScroll += ticks
        let notches = photoScroll / 3
        guard notches != 0 else { return }
        photoScroll -= notches * 3
        if snapshot.photos.viewing { return photosAction(.step(notches)) }
        snapshot.photos.scrollRow = min(max(snapshot.photos.scrollRow + notches, 0),
                                        PhotosLayout.maxRow(snapshot.photos.count))
        photosChanged()
    }

    /// The widget and the centre show a new photo every few seconds.
    private func slideshow(now: Date) {
        guard isOnGlasses(.photos), solo != .photos, snapshot.photos.count > 1,
              now.timeIntervalSince(lastSlide) >= 8 else { return }
        lastSlide = now
        snapshot.photos.current = (snapshot.photos.current + 1) % snapshot.photos.count
        photosChanged()
    }

    // ------------------------------------------------------------------ YouTube

    /// The video over the whole canvas.
    private var watchingYouTube: Bool {
        solo == .youtube && !clearView && snapshot.youtube.page == .player
    }

    private func youtubeAction(_ action: YouTubeAction) {
        switch action {
        case let .page(page):
            snapshot.youtube.page = page
            if page == .player { scheduleCursorHide() }
        case .togglePlay:
            if snapshot.youtube.hasVideo { youtubePlayer.togglePlay() } else { playNextVideo() }
        case .next: playNextVideo()
        case .skipAd: youtubePlayer.skipAd()
        case let .seek(seconds): youtubePlayer.seek(by: seconds)
        case .search:
            keyboardTarget == .youtubeSearch ? endTyping() : beginYouTubeSearch()
        case let .play(video): playVideo(video)
        case let .playQueued(index):
            guard snapshot.youtube.queue.indices.contains(index) else { return }
            playVideo(snapshot.youtube.queue.remove(at: index))
        case let .enqueue(video):
            if !snapshot.youtube.queue.contains(video) { snapshot.youtube.queue.append(video) }
        case let .dequeue(index):
            if snapshot.youtube.queue.indices.contains(index) { snapshot.youtube.queue.remove(at: index) }
        }
    }

    private func playVideo(_ video: YouTubeVideo) {
        var youtube = snapshot.youtube
        youtube.hasVideo = true
        youtube.videoId = video.id
        youtube.title = video.title
        youtube.channel = video.channel
        youtube.isLive = video.isLive
        youtube.elapsed = 0
        youtube.duration = 0
        youtube.isPlaying = false
        youtube.upNext = []
        youtube.queue.removeAll { $0.id == video.id }
        // Picked while the app is up: watch it.
        if solo == .youtube { youtube.page = .player }
        defer { if watchingYouTube { scheduleCursorHide() } }
        snapshot.youtube = youtube
        youtubePlayer.play(video.id)
        loadUpNext(for: video.id)
    }

    /// The queue first, then whatever YouTube would play next.
    private func playNextVideo() {
        if !snapshot.youtube.queue.isEmpty {
            playVideo(snapshot.youtube.queue.removeFirst())
        } else if let next = snapshot.youtube.upNext.first(where: { $0.id != snapshot.youtube.videoId }) {
            playVideo(next)
        } else if let first = snapshot.youtube.home.first, !snapshot.youtube.hasVideo {
            playVideo(first)
        }
    }

    private func youtubeChanged(_ state: YouTubePlayer.State) {
        var youtube = snapshot.youtube
        let wasEnded = youtube.hasVideo && !youtube.isPlaying && youtube.duration > 0
            && youtube.elapsed >= youtube.duration - 0.5
        let movedOn = !state.videoId.isEmpty && state.videoId != youtube.videoId
        youtube.hasVideo = state.hasVideo
        youtube.videoId = state.videoId
        if !state.title.isEmpty { youtube.title = state.title }
        if !state.channel.isEmpty { youtube.channel = state.channel }
        youtube.isPlaying = state.isPlaying
        youtube.isAd = state.isAd
        youtube.canSkipAd = state.canSkipAd
        youtube.notice = state.notice
        if !state.isAd {
            youtube.elapsed = state.elapsed
            youtube.duration = state.duration
            if state.duration > 0 { youtube.isLive = false }
        }
        snapshot.youtube = youtube
        if movedOn { loadUpNext(for: state.videoId) }
        // Finished: on to the queue, or Up next. Once, not every second it stays ended.
        if state.ended, !state.isAd, !wasEnded { playNextVideo() }
    }

    private func loadUpNext(for id: String) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return }
        Task {
            let videos = await YouTubePlayer.videos(at: url) ?? []
            guard snapshot.youtube.videoId == id else { return }
            snapshot.youtube.upNext = videos.filter { $0.id != id }
            // The page's own title and channel are better than nothing while the player loads.
            if let this = videos.first(where: { $0.id == id }), snapshot.youtube.channel.isEmpty {
                snapshot.youtube.channel = this.channel
            }
        }
    }

    /// Home and Subscriptions, fetched when the app comes up and again after a while.
    private func loadYouTube(_ tab: HudSnapshot.YouTube.Tab, force: Bool = false) {
        let url: URL
        switch tab {
        case .home: url = YouTubePlayer.homeURL
        case .subscriptions: url = YouTubePlayer.subscriptionsURL
        case .search: return searchYouTube()
        }
        if !force, let last = youtubeLoaded[tab], Date().timeIntervalSince(last) < 15 * 60 { return }
        youtubeLoaded[tab] = Date()
        snapshot.youtube.loading = true
        Task {
            let videos = await YouTubePlayer.videos(at: url)
            snapshot.youtube.loading = false
            guard let videos else {
                youtubeLoaded[tab] = nil
                snapshot.youtube.problem = "Couldn\u{2019}t reach YouTube"
                return
            }
            snapshot.youtube.problem = ""
            switch tab {
            case .home: snapshot.youtube.home = videos
            case .subscriptions: snapshot.youtube.subscriptions = videos
            case .search: break
            }
        }
    }

    private func searchYouTube() {
        let query = snapshot.youtube.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let url = YouTubePlayer.searchURL(query) else {
            snapshot.youtube.results = []
            return
        }
        snapshot.youtube.loading = true
        if snapshot.youtube.page == .browse {
            snapshot.youtube.tab = .search
            snapshot.youtube.scrollRow = 0
        }
        Task {
            let videos = await YouTubePlayer.videos(at: url)
            // Typing went on while this was out: a newer search will answer.
            guard snapshot.youtube.query.trimmingCharacters(in: .whitespaces) == query else { return }
            snapshot.youtube.loading = false
            snapshot.youtube.problem = videos == nil ? "Couldn\u{2019}t reach YouTube" : ""
            snapshot.youtube.results = videos ?? []
            if snapshot.youtube.tab == .search { snapshot.youtube.scrollRow = 0 }
        }
    }

    private func youtubeClick(at point: CGPoint, size: CGSize, alone: Bool) {
        guard alone else {
            // In a slot: the video is the button.
            if snapshot.youtube.hasVideo { youtubePlayer.togglePlay() }
            return
        }
        switch YouTubeAppLayout.target(at: point, snapshot.youtube, in: size) {
        case let .tab(tab):
            snapshot.youtube.tab = tab
            snapshot.youtube.scrollRow = 0
            if tab == .search, snapshot.youtube.query.isEmpty {
                beginYouTubeSearch()
            } else if tab != .search {
                loadYouTube(tab)
            }
        case .nowPlaying: snapshot.youtube.page = .player
        case let .card(index):
            let list = snapshot.youtube.list(snapshot.youtube.tab)
            if list.indices.contains(index) { playVideo(list[index]) }
        case .video: youtubePlayer.togglePlay()
        case nil: break
        }
    }

    /// Browsing, the wheel moves the grid a row at a time; over the video, it scrubs by five
    /// seconds.
    private func youtubeScrolled(_ ticks: Int, at point: CGPoint, size: CGSize, alone: Bool) {
        youtubeScroll += ticks
        let step = 3
        guard abs(youtubeScroll) >= step else { return }
        let notches = youtubeScroll / step
        youtubeScroll -= notches * step
        if alone, snapshot.youtube.page == .browse {
            let count = snapshot.youtube.list(snapshot.youtube.tab).count
            snapshot.youtube.scrollRow = min(max(snapshot.youtube.scrollRow + notches, 0),
                                             YouTubeAppLayout.maxRow(count, in: size))
        } else if snapshot.youtube.hasVideo, !snapshot.youtube.isLive {
            // Down the page is on in the video.
            youtubePlayer.seek(by: Double(notches) * 5)
        }
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

    func beginYouTubeSearch() {
        if keyboardTarget == .address { snapshot.browser.isEditingAddress = false }
        keyboardTarget = .youtubeSearch
        draft = snapshot.youtube.query
        snapshot.youtube.isEditingQuery = true
    }

    func endTyping() {
        if isRemote {
            if remoteState?.keyboard != nil { remoteLink.send(["t": "endTyping"]) }
            return
        }
        if keyboardTarget == .youtubeSearch { snapshot.youtube.isEditingQuery = false }
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
        if isRemote {
            remoteLink.send(["t": "draft", "text": new])
            // Typing into a page, the same sentinel as here: gone, the Android phone deletes one
            // past what was typed and puts it back, and so does this field.
            let target = shownKeyboardTarget
            remoteDraft = (target == .page || target == .mac) && !new.hasPrefix(Self.sentinel) ? Self.sentinel + new : new
            return
        }
        switch keyboardTarget {
        case .address:
            draft = new
            snapshot.browser.url = new
        case .note:
            draft = new
            snapshot.note.text = new
        case .youtubeSearch:
            draft = new
            snapshot.youtube.query = new
            // Results as you type, once the typing pauses; the video plays on.
            youtubeSearchDebounce?.invalidate()
            youtubeSearchDebounce = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
                MainActor.assumeIsolated { self.searchYouTube() }
            }
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
        if isRemote {
            remoteLink.send(["t": "submit"])
            // Return on the Mac starts a new line there, and an empty field here.
            if shownKeyboardTarget == .mac { remoteDraft = Self.sentinel }
            return
        }
        switch keyboardTarget {
        case .address:
            if let url = AddressInput.url(from: draft) { browser.load(url) }
            endTyping()
        case .page:
            browser.submit()
            endTyping()
        case .note:
            endTyping()
        case .youtubeSearch:
            youtubeSearchDebounce?.invalidate()
            searchYouTube()
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
        if placed(.photos) {
            Task { await photosProvider.start() }
        }
        photosChanged()
        if placed(.sky) || solo == .sky { updateSky(force: true) }
        // Hidden or cleared away, captions keep listening (the phone shows a red dot); taken
        // off the glasses, they stop.
        if captions.state.isListening && !placed(.captions) { captions.stop() }
        if placed(.youtube) {
            loadYouTube(.home)
            if youtubeSubscriptions { loadYouTube(.subscriptions) }
        } else if snapshot.youtube.hasVideo {
            // Taken off the glasses: nothing should go on playing unseen.
            youtubePlayer.stop()
            snapshot.youtube.page = .browse
        }
    }

    /// Every second, with the clock.
    private func tickWidgets() {
        let now = Date()
        if timer.isRunning || snapshot.timer.state == .done { timerChanged(now: now) }
        music.tick()
        activityProvider.tick(now: now)
        captions.tick(now: now)
        slideshow(now: now)
        updateSky()
        updateOverhead(now: now)
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

    // ------------------------------------------------------------------ Remote Connect

    private func startRemoteConnect() {
        remoteLink.hosting = remoteHosting
        remoteLink.onKeyframe = { [weak self] in self?.hostStreamer?.requestKeyframe() }
        remoteLink.onHostVideo = { [weak self] o in
            self?.androidVideo = (o["id"] as? String ?? "", (o["time"] as? NSNumber)?.doubleValue ?? 0,
                                  o["playing"] as? Bool ?? false, Date())
        }
        remoteLink.onStatus = { [weak self] status in
            guard let self else { return }
            self.remoteStatus = status
            if case .connected = status, self.remoteLink.hosting { self.startHosting() } else { self.stopHosting() }
            if case .connected = status {
                // In: the code has done its job.
                self.showingRemoteConnect = false
                self.sendTheme()
            } else if self.remoteState != nil {
                self.remoteState = nil
                self.updateCamera()
                self.remoteDraft = ""
                self.appPadSetAside = false
                self.padChanged()
            }
        }
        remoteLink.onState = { [weak self] state in self?.remoteStateArrived(state) }
        if let pairing = RemotePairingStore.load() { remoteLink.connect(pairing) }
    }

    private func remoteStateArrived(_ state: RemoteState) {
        let old = remoteState
        let padBefore = pad
        if old == nil || old?.keyboard != state.keyboard { remoteDraft = state.draft }
        if old == nil {
            // Taking over (not remote yet, so this is this phone's own): the keyboard and the
            // cursor step aside.
            if keyboardTarget != nil { endTyping() }
            putCursorAway()
        }
        if old?.solo != state.solo { appPadSetAside = false }
        remoteState = state
        updateCamera()
        if pad != padBefore { padChanged() }
    }

    /// A scanned code or an opened `thehud://` link.
    @discardableResult
    func pair(with link: String) -> Bool {
        guard let pairing = RemotePairing(link: link) else { return false }
        RemotePairingStore.save(pairing)
        remoteLink.connect(pairing)
        return true
    }

    /// REMOTE or HOST: a change reconnects in the new mode.
    func setRemoteHosting(_ on: Bool) {
        guard on != remoteHosting else { return }
        remoteHosting = on
        UserDefaults.standard.set(on, forKey: "remoteHosting")
        remoteLink.hosting = on
        if let pairing = remoteLink.pairing { remoteLink.connect(pairing) }
    }

    /// The glasses this phone draws for, plugged into it: Host mode leaves them be.
    private var glassesScene: Bool {
        UIApplication.shared.connectedScenes.contains { $0.delegate is GlassesSceneDelegate }
    }

    /// Host mode is in: this phone's glasses are drawn and sent, as if they were plugged in here.
    private func startHosting() {
        guard hostStreamer == nil, !glassesScene,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.role == .windowApplication }) else { return }
        let streamer = HostStreamer(link: remoteLink)
        streamer.overlay = { [weak self] in self?.hostOverlay() ?? ([:], nil) }
        streamer.macPicture = { [weak self] in self?.desktopLink.latestPicture }
        desktopLink.decodesPictures = true
        streamer.start(in: scene)
        hostStreamer = streamer
        hostSoundChanged()
        glassesConnected = true
    }

    /// The Android phone plays the video either way, for the picture; the sound is the glasses'
    /// unless it is asked for here. Here, it plays on with the phone locked, as a music app would.
    private func hostSoundChanged() {
        guard hostStreamer != nil else { return }
        youtubePlayer.muted = !hostSoundHere
        if hostSoundHere {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    /// Whether the Android phone's video goes its own way for now: while this phone is locked its
    /// silent player may stop, and that must not stop the one with the sound.
    private var hostVideoHeld: Bool {
        !hostSoundHere && (UIApplication.shared.applicationState != .active || Date() < hostHoldUntil)
    }

    /// Locked in Host mode: the Android phone draws the glasses itself meanwhile.
    private var hostStandingIn = false

    private func hostStandIn(_ on: Bool) {
        guard hostStreamer != nil, on != hostStandingIn else { return }
        hostStandingIn = on
        remoteLink.send(on ? RemoteWire.standIn(true, arrangement: arrangement, solo: solo, clearView: clearView)
                           : RemoteWire.standIn(false))
        if !on { hostStreamer?.requestKeyframe() }
        // The Mac: the Android phone connects to it while it stands in, so this phone lets go, or
        // the two would keep taking it from each other.
        panelsChanged()
    }

    /// Unlocked again: this phone's silent player jumps to where the Android phone's has got to.
    private func hostCatchUp() {
        guard hostStreamer != nil, !hostSoundHere, let a = androidVideo,
              a.id == youtubePlayer.state.videoId, Date().timeIntervalSince(a.at) < 5 else { return }
        let target = a.time + (a.playing ? Date().timeIntervalSince(a.at) : 0)
        youtubePlayer.seek(by: target - youtubePlayer.state.elapsed)
        if youtubePlayer.state.isPlaying != a.playing { youtubePlayer.togglePlay() }
        hostHoldUntil = Date().addingTimeInterval(3)
    }

    /// What the film of the glasses cannot hold, in the canvas's points.
    private func hostOverlay() -> (json: [String: Any], mac: CGRect?) {
        let screen = GlassesScreen(snapshot: snapshot, arrangement: arrangement, solo: solo, clearView: clearView)
        func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height].map { Double($0) } }
        var o: [String: Any] = [:]
        // Drawn by the Android phone, not filmed: it moves as soon as this arrives.
        if let cursor = screen.shownCursor { o["cursor"] = [Double(cursor.x), Double(cursor.y)] }
        let y = snapshot.youtube
        if y.hasVideo, !y.videoId.isEmpty {
            var video: [String: Any] = ["id": y.videoId, "t": y.elapsed, "playing": y.isPlaying, "ad": y.isAd,
                                        "muted": hostSoundHere, "hold": hostVideoHeld]
            if let place = screen.videoPlace {
                video["box"] = rect(place.box)
                video["corner"] = Double(place.corner)
            }
            o["video"] = video
        }
        let mac = screen.macPicture
        if let mac { o["mac"] = rect(mac) }
        return (o, mac)
    }

    private func stopHosting() {
        guard let streamer = hostStreamer else { return }
        streamer.stop()
        hostStreamer = nil
        hostStandingIn = false
        desktopLink.decodesPictures = false
        youtubePlayer.muted = false
        glassesConnected = glassesScene
    }

    /// Back to this phone's own glasses, and the pairing forgotten.
    func forgetRemote() {
        RemotePairingStore.save(nil)
        remoteLink.disconnect()
    }

    func settingsChanged() {
        recognizer.settings = trackpad
        rail.scrollSpeed = trackpad.scrollSpeed
        rail.naturalScrolling = trackpad.naturalScrolling
        remote.air.speed = Double(trackpad.trackingSpeed)
        let defaults = UserDefaults.standard
        defaults.set(trackpad.trackingSpeed, forKey: "trackingSpeed")
        defaults.set(trackpad.scrollSpeed, forKey: "scrollSpeed")
        defaults.set(trackpad.naturalScrolling, forKey: "naturalScrolling")
        defaults.set(trackpad.tapToClick, forKey: "tapToClick")
        defaults.set(trackpad.momentumScrolling, forKey: "momentumScrolling")
        defaults.set(config.pitch, forKey: "pitch")
        defaults.set(config.contrast, forKey: "contrast")
    }

    /// The theme reaches the store every view reads its accent from, the touchpad, the icon and the
    /// Android phone.
    func themeChanged() {
        ThemeStore.shared.color = themeColor
        config.colorway = themeColor.colorway
        sendTheme()
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != themeColor.iconName else { return }
        app.setAlternateIconName(themeColor.iconName) { error in
            if let error { print("icon: \(error.localizedDescription)") }
        }
    }

    /// The Android phone draws its own glasses in Remote mode, and its phone screen in both.
    private func sendTheme() {
        guard case .connected = remoteStatus else { return }
        remoteLink.send(RemoteWire.theme(themeColor))
    }

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
        }
        recognizer.settings = trackpad
        rail.scrollSpeed = trackpad.scrollSpeed
        rail.naturalScrolling = trackpad.naturalScrolling
        ThemeStore.shared.color = themeColor
        config.colorway = themeColor.colorway
    }

    func surfaceSizeChanged(to size: CGSize) {
        recognizer.surfaceSize = size
    }

    private func handle(_ event: GestureEvent) {
        if isRemote {
            remoteLink.send(RemoteWire.message(for: event))
            return
        }
        pointer.apply(event)

        // Put away for being idle or the phone being locked: the first touch only brings it
        // back, so nothing is clicked where it could not be seen.
        if cursorAsleep {
            cursorAsleep = false
            snapshot.cursor = pointer.position
            switch event {
            case .tapClick, .rightClick:
                scheduleCursorHide()
                return
            default: break
            }
        }

        switch event {
        case let .scrollFling(vx, vy): startMomentum(vx: vx, vy: vy)
        case .move:
            momentum.stop()
            pointerMoved()
        case .tapClick: click()
        case .rightClick where watchingYouTube:
            // Out of the video, back to the lists; it plays on in the corner.
            snapshot.youtube.page = .browse
            scheduleCursorHide()
        case .rightClick where solo == .sky && !clearView:
            // The sky's wheel zooms; the other button puts the view back.
            snapshot.skyView.recentre()
            saveSkyView()
        case .rightClick:
            switch layout.hitTest(pointer.position) {
            case let .mac(p):
                desktopFocused = true
                desktopLink.send(.click(x: p.x, y: p.y, button: 1))
            case let .widget(.clock, p, _) where solo == .clock && ClockAppLayout.timerCard.contains(p):
                timer.reset()
                timerChanged()
            case let .centre(.clock, p, size) where ClockAppLayout.timerCard(in: size).contains(p):
                timer.reset()
                timerChanged()
            case .centre(.youtube, _, _) where snapshot.youtube.page == .player:
                // Out of the video, back to the lists; it plays on in their corner.
                snapshot.youtube.page = .browse
            case .widget(.photos, _, _) where solo == .photos && snapshot.photos.viewing:
                snapshot.photos.viewing = false
                photosChanged()
            case .centre(.prompter, _, _):
                prompterAction(.restart)
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
    /// desktop. Anywhere else it waits a minute untouched, then goes: left lying on the glasses
    /// it sits over whatever the wearer is looking at, out in the street.
    private func scheduleCursorHide() {
        cursorHideTimer?.invalidate()
        let fullscreen = snapshot.browser.isFullscreen || watchingYouTube
        cursorHideTimer = Timer.scheduledTimer(withTimeInterval: fullscreen ? 2.5 : 60,
                                               repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if fullscreen {
                    if self.snapshot.browser.isFullscreen || self.watchingYouTube { self.snapshot.cursor = nil }
                } else {
                    self.putCursorAway()
                }
            }
        }
    }

    /// The phone was locked or left: the cursor goes, and so does pointing with the phone.
    private func phoneWentAway() {
        phoneActive = false
        updateCamera()
        putCursorAway()
        remote.stop()
        remoteTouches.removeAll()
        contacts = []
    }

    private func phoneCameBack() {
        phoneActive = true
        updateCamera()
        if pad == .remote { remote.start() }
        hostCatchUp()
    }

    /// Off the glasses until the trackpad is next touched.
    private func putCursorAway() {
        cursorHideTimer?.invalidate()
        cursorAsleep = true
        snapshot.cursor = nil
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
