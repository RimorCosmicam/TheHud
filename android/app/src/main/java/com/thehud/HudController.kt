package com.thehud

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import android.graphics.Bitmap
import android.view.TextureView
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.thehud.apps.AppsProvider
import com.thehud.apps.HudAccessibility
import com.thehud.core.AppsLayout
import com.thehud.core.BrowserMetrics
import com.thehud.core.ClockAppLayout
import com.thehud.core.MapsLayout
import com.thehud.core.MusicLayout
import com.thehud.core.SkyCatalogue
import com.thehud.core.SkyLayer
import com.thehud.core.SkyModel
import com.thehud.core.SkyProjection
import com.thehud.core.SkyTarget
import com.thehud.core.SkyView
import com.thehud.core.YouTubeAppLayout
import com.thehud.core.YouTubeVideo
import com.thehud.data.ActivityProvider
import com.thehud.data.CalendarProvider
import com.thehud.data.CaptionsEngine
import com.thehud.data.LatLon
import com.thehud.data.LocationProvider
import com.thehud.data.MapGround
import com.thehud.data.MapsService
import com.thehud.data.MusicProvider
import com.thehud.data.NavigationTracker
import com.thehud.data.OverheadProvider
import com.thehud.data.RoutePlan
import com.thehud.data.WorldClocks
import com.thehud.desktop.DesktopLink
import com.thehud.desktop.DesktopWire
import com.thehud.glasses.GlassesPresenter
import com.thehud.remote.RemoteMotion
import com.thehud.youtube.YouTubeData
import com.thehud.youtube.YouTubePlayer
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import com.thehud.core.GlassesHit
import com.thehud.core.GlassesLayout
import com.thehud.core.HudArrangement
import com.thehud.core.HudEdge
import com.thehud.core.HudPanelKind
import com.thehud.core.HudScene
import com.thehud.core.HudSnapshot
import com.thehud.core.HudSpot
import com.thehud.core.HudTimer
import com.thehud.core.Pointer
import com.thehud.data.OpenMeteo
import com.thehud.data.Whereabouts
import com.thehud.touchpad.GestureEvent
import com.thehud.touchpad.PhysicsMomentumScroller
import com.thehud.web.AddressInput
import com.thehud.web.HomePage
import com.thehud.web.WebTab
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Every button on the phone lands here as one of these. */
sealed interface PhoneAction {
    data object Back : PhoneAction
    data object Forward : PhoneAction
    data object Reload : PhoneAction
    data object Home : PhoneAction
    data object Favorite : PhoneAction
    data object Address : PhoneAction
    data object Keyboard : PhoneAction
    data object Settings : PhoneAction
    data object ClearView : PhoneAction
    data class TapPanel(val kind: HudPanelKind) : PhoneAction
    data class Solo(val kind: HudPanelKind) : PhoneAction
    data class Place(val kind: HudPanelKind, val spot: HudSpot) : PhoneAction
    data class Scene(val index: Int) : PhoneAction
    data class ResetScene(val index: Int) : PhoneAction
    data class Layout(val edge: HudEdge?) : PhoneAction
    data class EditGlasses(val on: Boolean) : PhoneAction
    data class SelectTab(val index: Int) : PhoneAction
    data class CloseTab(val index: Int) : PhoneAction
    data object NewTab : PhoneAction
    data class Pad(val pad: PhonePad) : PhoneAction
    data class Timer(val action: TimerAction) : PhoneAction
    data class Note(val action: NoteAction) : PhoneAction
    data class Music(val action: MusicAction) : PhoneAction
    data object Captions : PhoneAction
    data class YouTube(val action: YouTubeAction) : PhoneAction
    data class Sky(val action: SkyAction) : PhoneAction
    data class Maps(val action: MapsLayout.Target, val index: Int = 0) : PhoneAction
    data class Remote(val zone: RemoteZone, val phase: RemotePhase) : PhoneAction
    data class MacWindow(val id: Long?) : PhoneAction
}

enum class KeyboardTarget { address, page, note, mapSearch, mac, youtubeSearch, apps }

/** What the lower half of the cover screen is: the touchpad, the phone pointed like a remote, or the app's own controls. */
enum class PhonePad { touchpad, remote, app }

enum class RemoteZone { click, scroll, rightClick, centre }
enum class RemotePhase { began, ended }

sealed interface MusicAction {
    data object PlayPause : MusicAction
    data object Next : MusicAction
    data object Previous : MusicAction
    data class Seek(val by: Double) : MusicAction
}

sealed interface YouTubeAction {
    data object TogglePlay : YouTubeAction
    data object Next : YouTubeAction
    data object SkipAd : YouTubeAction
    data class Seek(val by: Double) : YouTubeAction
    data class Tab(val tab: HudSnapshot.YouTube.Tab) : YouTubeAction
    data object Search : YouTubeAction
    data class Play(val video: YouTubeVideo) : YouTubeAction
    data class PlayQueued(val index: Int) : YouTubeAction
    data class Enqueue(val video: YouTubeVideo) : YouTubeAction
    data class Dequeue(val index: Int) : YouTubeAction
    data class Page(val page: HudSnapshot.YouTube.Page) : YouTubeAction
}

sealed interface SkyAction {
    data class Look(val pan: Double, val tilt: Double) : SkyAction
    data class Zoom(val factor: Double) : SkyAction
    data object Recentre : SkyAction
    data class Toggle(val layer: SkyLayer) : SkyAction
    data class Select(val id: String?) : SkyAction
}

sealed interface TimerAction {
    data object Toggle : TimerAction
    data object Reset : TimerAction
    data class Set(val minutes: Int) : TimerAction
    data class Add(val minutes: Int) : TimerAction
}

sealed interface NoteAction {
    data object Write : NoteAction
    data object Clear : NoteAction
    /** Points to roll the note by on the glasses; negative infinity goes back to the top. */
    data class Scroll(val by: Float) : NoteAction
}

/** The apps whose controls can take the cover screen's lower half. */
val HudPanelKind.hasPhoneControls get() = this in setOf(HudPanelKind.sky, HudPanelKind.music, HudPanelKind.clock,
    HudPanelKind.captions, HudPanelKind.note, HudPanelKind.youtube, HudPanelKind.map)

val HudPanelKind.padTitle get() = if (this == HudPanelKind.clock) "TIMER" else title

/**
 * The app's one brain, as on the iPhone: what is on the glasses, where the cursor is, what the
 * keyboard is typing into. Both screens draw from its state; the pad and the buttons call in.
 */
object HudController {
    private lateinit var app: Context
    private lateinit var prefs: SharedPreferences
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val main = Handler(Looper.getMainLooper())
    private val json = Json { ignoreUnknownKeys = true }

    var snapshot by mutableStateOf(HudSnapshot(weather = null))
        private set
    var arrangement by mutableStateOf(HudArrangement.standard)
        private set
    var solo by mutableStateOf<HudPanelKind?>(null)
        private set
    var clearView by mutableStateOf(false)
        private set
    var scenes by mutableStateOf(HudScene.presets)
        private set
    var sceneIndex by mutableStateOf(0)
        private set
    var editingGlasses by mutableStateOf(false)
        private set
    var keyboardTarget by mutableStateOf<KeyboardTarget?>(null)
        private set
    var draft by mutableStateOf("")
        private set
    var glassesConnected by mutableStateOf(false)
        private set
    var showingSettings by mutableStateOf(false)
    var pad by mutableStateOf(PhonePad.touchpad)
        private set
    /** Fingers on the pad, for the halftone to ripple under. */
    val touches = mutableStateListOf<Offset>()

    var favorites by mutableStateOf(HomePage.defaults)
        private set

    val tabs = mutableStateListOf<WebTab>()
    var activeTab by mutableStateOf(0)
        private set
    val browser: WebTab? get() = tabs.getOrNull(activeTab)

    /** The phone's own pictures for the glasses: the map's ground and the album art. */
    var mapGround by mutableStateOf<ImageBitmap?>(null)
        private set
    var artwork by mutableStateOf<ImageBitmap?>(null)
        private set
    var youtube: YouTubePlayer? = null
        private set
    val apps by lazy { AppsProvider(app) }
    /** Caption sessions and the like changed: the settings page reads this to redraw. */
    var settingsVersion by mutableStateOf(0)
        private set
    var trackpadSpeed by mutableStateOf(1f)
        private set
    var captionsLanguage by mutableStateOf(CaptionsEngine.defaultLanguage)
        private set
    var stepGoal by mutableStateOf(8000)
        private set
    var youtubeSubscriptions by mutableStateOf(false)
        private set

    private lateinit var location: LocationProvider
    private lateinit var calendar: CalendarProvider
    private lateinit var activity: ActivityProvider
    private lateinit var music: MusicProvider
    private lateinit var captions: CaptionsEngine
    private lateinit var desktop: DesktopLink
    private lateinit var remote: RemoteMotion
    private lateinit var overhead: OverheadProvider
    private var here: LatLon? = null
    private var skyCatalogue: SkyCatalogue? = null
    private var lastSky = 0L
    private var lastSkyAt: LatLon? = null
    private var computingSky = false
    private var lastCalendar = 0L

    // The map: what the raster covers, and the search and the route.
    private var mapSpan = 300
    private var groundCentre: LatLon? = null
    private var groundSpan = 0.0
    private var groundFetchedAt = 0L
    private var groundPlanSpan = 0.0
    private var fetchingGround = false
    private var zoomRefetch: Runnable? = null
    private var searchJob: Job? = null
    private var searchResults = listOf<MapsService.Result>()
    private var tracker: NavigationTracker? = null

    // YouTube's lists, and when they were last fetched.
    private var youtubeFetchedAt = mutableMapOf<HudSnapshot.YouTube.Tab, Long>()
    private var youtubeSearchJob: Job? = null
    private var youtubeScrollTicks = 0
    private var youtubeCursorHide: Runnable? = null

    // The remote's buttons.
    private var remoteDragTimer: Runnable? = null
    private var remoteDragging = false

    private var pointer = Pointer()
    private val momentum by lazy { PhysicsMomentumScroller(scope) { v, _ -> scroll(v) } }
    private var timer = HudTimer()
    private var glassesContext: Context? = null
    private var lastHover = 0L
    private var cursorHide: Runnable? = null

    val layout: GlassesLayout
        get() = GlassesLayout(arrangement, solo, clearView, snapshot.browser.tabs.size, activeTab, snapshot.browser.isFullscreen,
            snapshot.desktop.aspect)

    fun isOnGlasses(kind: HudPanelKind): Boolean =
        if (clearView) false else solo?.let { it == kind } ?: arrangement.isShown(kind)

    fun start(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        prefs = app.getSharedPreferences("hud", Context.MODE_PRIVATE)
        // Map tiles are cached on the phone, as OpenStreetMap's tile policy asks.
        runCatching { android.net.http.HttpResponseCache.install(java.io.File(app.cacheDir, "http"), 64L * 1024 * 1024) }
        loadScenes()
        prefs.getString("favorites", null)?.let {
            runCatching { json.decodeFromString(ListSerializer(HomePage.Favorite.serializer()), it) }.getOrNull()
        }?.let { favorites = it }
        snapshot = HudSnapshot.blank.copy(note = HudSnapshot.Note(prefs.getString("note", "") ?: ""))
        timer = HudTimer(setSeconds = prefs.getInt("timerSeconds", 300))
        trackpadSpeed = prefs.getFloat("trackpadSpeed", 1f)
        mapSpan = prefs.getInt("mapSpan", 300).coerceIn(120, 8000)
        stepGoal = prefs.getInt("stepGoal", 8000)
        captionsLanguage = prefs.getString("captionsLanguage", null) ?: CaptionsEngine.defaultLanguage
        youtubeSubscriptions = prefs.getBoolean("youtubeSubscriptions", false)
        val layers = prefs.getStringSet("skyLayers", null)?.mapNotNull { n -> SkyLayer.entries.firstOrNull { it.name == n } }?.toSet()
        snapshot = snapshot.copy(
            skyView = SkyView(layers = layers ?: SkyLayer.standard, fov = prefs.getFloat("skyFov", SkyView.STANDARD_FOV.toFloat()).toDouble()),
            youtube = snapshot.youtube.copy(showsSubscriptions = youtubeSubscriptions))

        overhead = OverheadProvider(scope)
        location = LocationProvider(app) { minimap, at, _ -> located(minimap, at) }
        calendar = CalendarProvider(app)
        activity = ActivityProvider(app, prefs) { snapshot = snapshot.copy(activity = it) }.also { it.goal = stepGoal }
        music = MusicProvider(app) { playing, art -> musicChanged(playing, art) }
        captions = CaptionsEngine(app) { snapshot = snapshot.copy(captions = it) }.also { it.language = captionsLanguage }
        desktop = DesktopLink(app) { d ->
            snapshot = snapshot.copy(desktop = d)
            if (!d.connected && keyboardTarget == KeyboardTarget.mac) endTyping()
        }
        remote = RemoteMotion(app) { dx, dy, _ -> remoteMoved(dx, dy) }
        scope.launch(Dispatchers.IO) {
            val catalogue = runCatching { SkyCatalogue(app.assets.open("sky.json").bufferedReader().use { it.readText() }) }.getOrNull()
            withContext(Dispatchers.Main) { skyCatalogue = catalogue; lastSky = 0 }
        }
        startProviders()
        tick()
        refreshWeather()
    }

    /** After a permission is granted, or settings come back: start whatever can now start. */
    fun startProviders() {
        activity.start()
        music.start()
        sensorsChanged()
        lastCalendar = 0
        settingsVersion++
    }

    /** Location and the Mac run only while something on the glasses needs them. */
    private fun sensorsChanged() {
        val needsLocation = isOnGlasses(HudPanelKind.map) || isOnGlasses(HudPanelKind.sky) || tracker != null
        if (needsLocation) location.start() else location.stop()
        if (isOnGlasses(HudPanelKind.mac)) desktop.start() else desktop.stop()
        if (pad == PhonePad.remote) remote.start() else remote.stop()
        if (isOnGlasses(HudPanelKind.youtube)) refreshYouTube(snapshot.youtube.tab)
        else if (youtube?.state?.hasVideo == true) {
            youtube?.stop()
            snapshot = snapshot.copy(youtube = snapshot.youtube.copy(hasVideo = false, isPlaying = false, page = HudSnapshot.YouTube.Page.browse))
        }
        if (isOnGlasses(HudPanelKind.apps)) refreshApps()
        else if (snapshot.apps.running != null) snapshot = snapshot.copy(apps = snapshot.apps.copy(running = null))
    }

    // ------------------------------------------------------------------ the glasses

    /** The glasses' window came up: pages are made in its context, so they lay out at its size. */
    fun glassesAttached(context: Context) {
        glassesContext = context
        glassesConnected = true
        if (tabs.isEmpty()) openTab(null)
        if (youtube == null) youtube = YouTubePlayer(context) { youtubeChanged(it) }
    }

    /** The Mac's picture goes to this view's surface. */
    fun attachMac(view: TextureView) = desktop.attach(view)

    fun glassesDetached() {
        glassesConnected = false
        tabs.forEach { it.detach() }
    }

    // ------------------------------------------------------------------ the clock and the weather

    private fun tick() {
        val now = Date()
        val is24 = android.text.format.DateFormat.is24HourFormat(app)
        val time = SimpleDateFormat(if (is24) "H:mm" else "h:mm", Locale.getDefault()).format(now)
        val meridiem = if (is24) null else SimpleDateFormat("a", Locale.getDefault()).format(now).uppercase()
        val clock = snapshot.clock.copy(
            time = time, meridiem = meridiem,
            weekday = SimpleDateFormat("EEEE", Locale.getDefault()).format(now).uppercase(),
            date = SimpleDateFormat("d MMMM", Locale.getDefault()).format(now).uppercase(),
            seconds = SimpleDateFormat("ss", Locale.US).format(now),
            hourHand = cal(now, java.util.Calendar.HOUR) + cal(now, java.util.Calendar.MINUTE) / 60.0,
            minuteHand = cal(now, java.util.Calendar.MINUTE) + cal(now, java.util.Calendar.SECOND) / 60.0,
            secondHand = cal(now, java.util.Calendar.SECOND).toDouble(),
            worldClocks = WorldClocks.now(now, is24),
        ).let { c ->
            // The calendar is read once a minute: it is a database query.
            if (calendar.allowed && System.currentTimeMillis() - lastCalendar > 60_000) {
                lastCalendar = System.currentTimeMillis()
                val next = calendar.nextEvent(is24 = is24)
                c.copy(nextEvent = next?.first, nextEventTime = next?.second, agenda = calendar.agenda(is24 = is24))
            } else if (!calendar.allowed) c.copy(nextEvent = null, nextEventTime = null, agenda = emptyList()) else c
        }
        val previous = snapshot.timer.state
        val reading = timer.reading(System.currentTimeMillis())
        snapshot = snapshot.copy(clock = clock, timer = reading)
        if (reading.state == HudSnapshot.TimerState.done && previous != HudSnapshot.TimerState.done) timerDone()
        music.tick()
        captions.tick()
        skyTick()
        main.postDelayed(::tick, 1000L - System.currentTimeMillis() % 1000L)
    }

    private fun cal(d: Date, field: Int) = java.util.Calendar.getInstance().apply { time = d }.get(field)

    /** Done: a buzz, and after a while the timer goes back to waiting. */
    private fun timerDone() {
        runCatching {
            app.getSystemService(android.os.Vibrator::class.java)
                ?.vibrate(android.os.VibrationEffect.createWaveform(longArrayOf(0, 300, 150, 300, 150, 600), -1))
        }
        main.postDelayed({
            if (timer.isDone(System.currentTimeMillis())) { timer = timer.reset(); snapshot = snapshot.copy(timer = timer.reading(System.currentTimeMillis())) }
        }, 12_000)
    }

    // ------------------------------------------------------------------ the map

    private val mapFillsCanvas get() = solo == HudPanelKind.map && !clearView

    private fun located(minimap: HudSnapshot.Minimap, at: LatLon) {
        here = at
        val nav = tracker?.update(at, is24 = android.text.format.DateFormat.is24HourFormat(app))
        snapshot = snapshot.copy(minimap = groundMinimap(minimap.copy(spanMetres = mapSpan)),
            maps = snapshot.maps.copy(navigation = nav ?: snapshot.maps.navigation))
        groundCheck()
        if (snapshot.maps.status == "WAITING FOR LOCATION" && snapshot.maps.query.isNotEmpty()) search(snapshot.maps.query)
    }

    /** How much ground the raster covers, how far one may walk before it is fetched again, and its pixels per point. */
    private data class GroundPlan(val span: Double, val room: Double, val scale: Float)

    private fun groundPlan(): GroundPlan {
        val span = mapSpan.toDouble()
        return if (mapFillsCanvas) {
            val ppm = 470.0 / span
            val safe = GlassesLayout.safeFrame
            val room = max(40.0, span * 0.4)
            GroundPlan(hypot(safe.width, safe.height) / ppm + room * 2 + span * 0.2, room, 1f)
        } else GroundPlan(span * HudSnapshot.Minimap.GROUND_OVERSIZE, span * 0.2, 2f)
    }

    private fun offsetOf(p: LatLon, centre: LatLon) = Offset(
        ((p.lon - centre.lon) * 111_320 * cos(Math.toRadians(centre.lat))).toFloat(), ((p.lat - centre.lat) * 111_320).toFloat())

    private fun groundMinimap(m: HudSnapshot.Minimap): HudSnapshot.Minimap {
        val centre = groundCentre ?: return m.copy(groundSpanMetres = 0.0, route = routeOffsets(here))
        val at = here ?: return m
        val o = offsetOf(at, centre)
        return m.copy(groundOffsetEast = o.x.toDouble(), groundOffsetNorth = o.y.toDouble(), groundSpanMetres = groundSpan,
            route = routeOffsets(centre))
    }

    private fun routeOffsets(centre: LatLon?): List<Offset> {
        val plan = tracker?.plan ?: return emptyList()
        val c = centre ?: return emptyList()
        return plan.points.map { offsetOf(it, c) }
    }

    private fun groundCheck() {
        if (!isOnGlasses(HudPanelKind.map) || fetchingGround) return
        val at = here ?: return
        val plan = groundPlan()
        val now = System.currentTimeMillis()
        val moved = groundCentre?.let { at.metres(it) } ?: Double.MAX_VALUE
        if (plan.span != groundPlanSpan || (moved > plan.room && now - groundFetchedAt > 3000)) fetchGround(at, plan)
    }

    private fun fetchGround(at: LatLon, plan: GroundPlan) {
        fetchingGround = true
        groundFetchedAt = System.currentTimeMillis()
        val side = (plan.span * 470.0 / mapSpan * plan.scale).toInt()
        scope.launch {
            val bitmap = MapGround.raster(at, plan.span, side)
            fetchingGround = false
            if (bitmap != null) {
                groundCentre = at; groundSpan = plan.span; groundPlanSpan = plan.span
                mapGround = bitmap.asImageBitmap()
                snapshot = snapshot.copy(minimap = groundMinimap(snapshot.minimap))
            } else groundPlanSpan = plan.span
        }
    }

    private fun zoomMap(factor: Double) {
        mapSpan = (mapSpan * factor).toInt().coerceIn(120, 8000)
        prefs.edit().putInt("mapSpan", mapSpan).apply()
        snapshot = snapshot.copy(minimap = snapshot.minimap.copy(spanMetres = mapSpan))
        zoomRefetch?.let(main::removeCallbacks)
        zoomRefetch = Runnable { groundPlanSpan = -1.0; groundCheck() }.also { main.postDelayed(it, 600) }
    }

    private fun search(query: String) {
        searchJob?.cancel()
        if (query.isBlank()) { searchResults = emptyList(); snapshot = snapshot.copy(maps = snapshot.maps.copy(results = emptyList(), status = null)); return }
        val near = here
        if (near == null) { snapshot = snapshot.copy(maps = snapshot.maps.copy(status = "WAITING FOR LOCATION")); return }
        snapshot = snapshot.copy(maps = snapshot.maps.copy(status = "SEARCHING"))
        searchJob = scope.launch {
            delay(500)
            val found = runCatching { MapsService.search(query, near) }.getOrNull() ?: emptyList()
            searchResults = found
            snapshot = snapshot.copy(maps = snapshot.maps.copy(results = found.map { it.place }, status = if (found.isEmpty()) "NO RESULTS" else null))
        }
    }

    private fun route(index: Int) {
        val to = searchResults.getOrNull(index) ?: return
        val from = here ?: return
        if (keyboardTarget == KeyboardTarget.mapSearch) endTyping()
        snapshot = snapshot.copy(maps = snapshot.maps.copy(status = "FINDING A ROUTE", results = emptyList()))
        scope.launch {
            val plan: RoutePlan? = runCatching { MapsService.route(from, to, snapshot.maps.driving) }.getOrNull()
            if (plan == null) { snapshot = snapshot.copy(maps = snapshot.maps.copy(status = "NO ROUTE")); return@launch }
            tracker = NavigationTracker(plan)
            routeTarget = to
            snapshot = snapshot.copy(maps = snapshot.maps.copy(status = null, query = "",
                navigation = tracker?.update(from, is24 = android.text.format.DateFormat.is24HourFormat(app))),
                minimap = groundMinimap(snapshot.minimap))
            sensorsChanged()
        }
    }

    private var routeTarget: MapsService.Result? = null

    private fun endRoute() {
        tracker = null; routeTarget = null
        snapshot = snapshot.copy(maps = snapshot.maps.copy(navigation = null, status = null), minimap = groundMinimap(snapshot.minimap))
        sensorsChanged()
    }

    private fun mapAction(target: MapsLayout.Target, index: Int) {
        when (target) {
            MapsLayout.Target.search -> if (keyboardTarget == KeyboardTarget.mapSearch) endTyping() else beginMapSearch()
            MapsLayout.Target.result -> route(index)
            MapsLayout.Target.endRoute -> endRoute()
            MapsLayout.Target.transport -> {
                snapshot = snapshot.copy(maps = snapshot.maps.copy(driving = !snapshot.maps.driving))
                routeTarget?.let { t -> searchResults = listOf(t); route(0) }
            }
            MapsLayout.Target.zoomIn -> zoomMap(1 / 1.6)
            MapsLayout.Target.zoomOut -> zoomMap(1.6)
            MapsLayout.Target.none -> {}
        }
    }

    // ------------------------------------------------------------------ the sky

    private fun skyTick() {
        if (!isOnGlasses(HudPanelKind.sky)) return
        val at = here ?: com.thehud.data.Whereabouts(app).last()?.let { LatLon(it.latitude, it.longitude) } ?: return
        val now = System.currentTimeMillis()
        val far = lastSkyAt?.let { at.metres(it) > 2000 } ?: true
        if (!computingSky && (now - lastSky > 30_000 || far)) {
            computingSky = true
            lastSky = now; lastSkyAt = at
            val catalogue = skyCatalogue
            val is24 = android.text.format.DateFormat.is24HourFormat(app)
            scope.launch(Dispatchers.Default) {
                val sky = runCatching { SkyModel.compute(Date(), at.lat, at.lon, if (solo == HudPanelKind.sky) catalogue else null, is24 = is24) }.getOrNull()
                withContext(Dispatchers.Main) {
                    computingSky = false
                    if (sky != null) snapshot = snapshot.copy(sky = sky.copy(hasLocation = true))
                }
            }
        }
        if (solo == HudPanelKind.sky && !clearView) {
            val layers = snapshot.skyView.layers
            overhead.refresh(at.lat, at.lon, SkyLayer.planes in layers, SkyLayer.iss in layers)
            snapshot = snapshot.copy(overhead = overhead.overhead(at.lat, at.lon))
        }
    }

    private fun skyAction(action: SkyAction) {
        val v = snapshot.skyView
        val next = when (action) {
            is SkyAction.Look -> v.looked(action.pan, action.tilt)
            is SkyAction.Zoom -> v.zoomed(action.factor)
            SkyAction.Recentre -> v.recentred()
            is SkyAction.Toggle -> v.toggled(action.layer)
            is SkyAction.Select -> v.copy(selected = if (action.id == v.selected) null else action.id)
        }
        snapshot = snapshot.copy(skyView = next)
        prefs.edit().putStringSet("skyLayers", next.layers.map { it.name }.toSet()).putFloat("skyFov", next.fov.toFloat()).apply()
        // The catalogue is only computed for the app; held up alone, it should come at once.
        if (action is SkyAction.Toggle) lastSky = 0
    }

    /** The thing nearest a click on the chart, picked or let go. */
    private fun skyClick(p: Offset) {
        val v = snapshot.skyView
        val pr = SkyProjection(com.thehud.glasses.skyFacing(snapshot.minimap.heading, v), v.fov, v.tilt)
        val best = SkyTarget.all(snapshot.sky, snapshot.overhead, v.layers).mapNotNull { t ->
            pr.project(t.az, t.alt)?.let { q -> t to hypot(q.x - p.x, q.y - p.y) }
        }.filter { it.second < 70 }.minByOrNull { it.second }?.first
        skyAction(SkyAction.Select(best?.id))
    }

    /** What the sky's list on the phone offers, nearest the eye first. */
    fun skyTargets(): List<SkyTarget> =
        SkyTarget.all(snapshot.sky, snapshot.overhead, snapshot.skyView.layers).filter { it.isUp }.sortedByDescending { it.alt }

    // ------------------------------------------------------------------ music

    private fun musicChanged(playing: HudSnapshot.NowPlaying?, art: Bitmap?) {
        snapshot = snapshot.copy(music = playing)
        artwork = art?.asImageBitmap()
    }

    private fun musicAction(action: MusicAction) {
        when (action) {
            MusicAction.PlayPause -> music.playPause()
            MusicAction.Next -> music.next()
            MusicAction.Previous -> music.previous()
            is MusicAction.Seek -> music.seek(action.by)
        }
    }

    val musicAllowed get() = music.allowed

    // ------------------------------------------------------------------ captions

    val captionsAllowed get() = captions.allowed

    fun changeCaptionsLanguage(tag: String) {
        captionsLanguage = tag
        captions.language = tag
        prefs.edit().putString("captionsLanguage", tag).apply()
    }

    fun changeStepGoal(goal: Int) {
        stepGoal = goal.coerceIn(1000, 50_000)
        activity.goal = stepGoal
        prefs.edit().putInt("stepGoal", stepGoal).apply()
    }

    fun changeTrackpadSpeed(speed: Float) {
        trackpadSpeed = speed.coerceIn(0.4f, 2.5f)
        prefs.edit().putFloat("trackpadSpeed", trackpadSpeed).apply()
    }

    fun changeYouTubeSubscriptions(on: Boolean) {
        youtubeSubscriptions = on
        prefs.edit().putBoolean("youtubeSubscriptions", on).apply()
        var y = snapshot.youtube.copy(showsSubscriptions = on)
        if (!on && y.tab == HudSnapshot.YouTube.Tab.subscriptions) y = y.copy(tab = HudSnapshot.YouTube.Tab.home, scrollRow = 0)
        snapshot = snapshot.copy(youtube = y)
        if (on) refreshYouTube(HudSnapshot.YouTube.Tab.subscriptions, force = true)
    }

    fun captionSessionsChanged() { settingsVersion++ }

    // ------------------------------------------------------------------ YouTube

    private fun youtubeChanged(state: YouTubePlayer.State) {
        val y = snapshot.youtube
        snapshot = snapshot.copy(youtube = y.copy(hasVideo = state.hasVideo, videoId = state.videoId,
            title = state.title.ifEmpty { y.title }, channel = state.channel.ifEmpty { y.channel },
            isPlaying = state.isPlaying, elapsed = state.elapsed, duration = state.duration,
            isAd = state.isAd, canSkipAd = state.canSkipAd, notice = state.notice,
            page = if (state.hasVideo) y.page else HudSnapshot.YouTube.Page.browse))
        if (state.ended) youtubeNext()
    }

    private fun refreshYouTube(tab: HudSnapshot.YouTube.Tab, force: Boolean = false) {
        val url = when (tab) {
            HudSnapshot.YouTube.Tab.home -> YouTubeData.HOME
            HudSnapshot.YouTube.Tab.subscriptions -> if (youtubeSubscriptions) YouTubeData.SUBSCRIPTIONS else return
            HudSnapshot.YouTube.Tab.search -> return
        }
        val now = System.currentTimeMillis()
        val fresh = now - (youtubeFetchedAt[tab] ?: 0) < 15 * 60_000 && snapshot.youtube.list(tab).isNotEmpty()
        if (fresh && !force) return
        youtubeFetchedAt[tab] = now
        snapshot = snapshot.copy(youtube = snapshot.youtube.copy(loading = true))
        scope.launch {
            val videos = YouTubeData.fetch(url)
            var y = snapshot.youtube.copy(loading = false, problem = if (videos == null) "YOUTUBE DID NOT ANSWER" else "")
            if (videos != null) y = if (tab == HudSnapshot.YouTube.Tab.home) y.copy(home = videos) else y.copy(subscriptions = videos)
            if (videos == null) youtubeFetchedAt.remove(tab)
            snapshot = snapshot.copy(youtube = y)
        }
    }

    private fun searchYouTube(query: String, now: Boolean = false) {
        youtubeSearchJob?.cancel()
        if (query.isBlank()) return
        youtubeSearchJob = scope.launch {
            if (!now) delay(800)
            snapshot = snapshot.copy(youtube = snapshot.youtube.copy(loading = true))
            val videos = YouTubeData.fetch(YouTubeData.searchUrl(query))
            snapshot = snapshot.copy(youtube = snapshot.youtube.copy(loading = false, scrollRow = 0,
                results = videos ?: snapshot.youtube.results, problem = if (videos == null) "YOUTUBE DID NOT ANSWER" else ""))
        }
    }

    private fun playYouTube(video: YouTubeVideo) {
        val player = youtube ?: return
        if (keyboardTarget == KeyboardTarget.youtubeSearch) endTyping()
        player.play(video.id)
        snapshot = snapshot.copy(youtube = snapshot.youtube.copy(hasVideo = true, videoId = video.id, title = video.title,
            channel = video.channel, isLive = video.isLive, elapsed = 0.0, duration = 0.0, notice = "",
            page = if (solo == HudPanelKind.youtube) HudSnapshot.YouTube.Page.player else snapshot.youtube.page))
        hideCursorWhileWatching()
        // Up next: what the watch page itself suggests.
        scope.launch {
            val related = YouTubeData.fetch("https://www.youtube.com/watch?v=" + video.id)?.filter { it.id != video.id }
            if (related != null && snapshot.youtube.videoId == video.id) snapshot = snapshot.copy(youtube = snapshot.youtube.copy(upNext = related))
        }
    }

    /** At the end: the queue first, then what YouTube suggests. */
    private fun youtubeNext() {
        val y = snapshot.youtube
        if (y.queue.isNotEmpty()) {
            snapshot = snapshot.copy(youtube = y.copy(queue = y.queue.drop(1)))
            playYouTube(y.queue.first())
        } else y.upNext.firstOrNull { it.id != y.videoId }?.let(::playYouTube)
    }

    private fun youtubeAction(action: YouTubeAction) {
        val y = snapshot.youtube
        when (action) {
            YouTubeAction.TogglePlay -> youtube?.togglePlay()
            YouTubeAction.Next -> youtubeNext()
            YouTubeAction.SkipAd -> youtube?.skipAd()
            is YouTubeAction.Seek -> youtube?.seek(action.by)
            is YouTubeAction.Tab -> {
                snapshot = snapshot.copy(youtube = y.copy(tab = action.tab, scrollRow = 0, page = HudSnapshot.YouTube.Page.browse))
                if (action.tab == HudSnapshot.YouTube.Tab.search) beginYouTubeSearch() else refreshYouTube(action.tab)
            }
            YouTubeAction.Search -> if (keyboardTarget == KeyboardTarget.youtubeSearch) endTyping() else {
                snapshot = snapshot.copy(youtube = y.copy(tab = HudSnapshot.YouTube.Tab.search, scrollRow = 0))
                beginYouTubeSearch()
            }
            is YouTubeAction.Play -> playYouTube(action.video)
            is YouTubeAction.PlayQueued -> y.queue.getOrNull(action.index)?.let { v ->
                snapshot = snapshot.copy(youtube = y.copy(queue = y.queue.filterIndexed { i, _ -> i != action.index }))
                playYouTube(v)
            }
            is YouTubeAction.Enqueue -> if (!y.hasVideo) playYouTube(action.video)
                else snapshot = snapshot.copy(youtube = y.copy(queue = y.queue + action.video))
            is YouTubeAction.Dequeue -> snapshot = snapshot.copy(youtube = y.copy(queue = y.queue.filterIndexed { i, _ -> i != action.index }))
            is YouTubeAction.Page -> {
                snapshot = snapshot.copy(youtube = y.copy(page = if (y.hasVideo) action.page else HudSnapshot.YouTube.Page.browse))
                if (action.page == HudSnapshot.YouTube.Page.player) hideCursorWhileWatching()
            }
        }
    }

    private fun hideCursorWhileWatching() {
        youtubeCursorHide?.let(main::removeCallbacks)
        youtubeCursorHide = Runnable {
            if (solo == HudPanelKind.youtube && snapshot.youtube.page == HudSnapshot.YouTube.Page.player) snapshot = snapshot.copy(cursor = null)
        }.also { main.postDelayed(it, 2500) }
    }

    private fun youtubeClick(p: Offset, alone: Boolean) {
        val y = snapshot.youtube
        if (!alone) { if (y.hasVideo) youtube?.togglePlay() else perform(PhoneAction.Solo(HudPanelKind.youtube)); return }
        when (val t = YouTubeAppLayout.target(p, y)) {
            is YouTubeAppLayout.Target.Tab -> youtubeAction(YouTubeAction.Tab(t.tab))
            YouTubeAppLayout.Target.NowPlaying -> youtubeAction(YouTubeAction.Page(HudSnapshot.YouTube.Page.player))
            is YouTubeAppLayout.Target.Card -> y.list(y.tab).getOrNull(t.index)?.let(::playYouTube)
            YouTubeAppLayout.Target.Video -> { youtube?.togglePlay(); hideCursorWhileWatching() }
            null -> {}
        }
    }

    private fun youtubeScrolled(ticks: Int, alone: Boolean) {
        val y = snapshot.youtube
        val watching = !alone || y.page == HudSnapshot.YouTube.Page.player
        youtubeScrollTicks += ticks
        // Three ticks a step: a row of videos while browsing, five seconds while watching.
        while (kotlin.math.abs(youtubeScrollTicks) >= 3) {
            val step = if (youtubeScrollTicks > 0) 1 else -1
            youtubeScrollTicks -= step * 3
            if (watching) { if (y.hasVideo && !y.isLive) youtube?.seek(step * 5.0) }
            else snapshot = snapshot.copy(youtube = snapshot.youtube.copy(
                scrollRow = (snapshot.youtube.scrollRow + step).coerceIn(0, YouTubeAppLayout.maxRow(y.list(y.tab).size))))
        }
    }

    // ------------------------------------------------------------------ Android apps

    private fun refreshApps() {
        val notice = if (apps.serviceEnabled) "" else "TURN ON THEHUD IN ACCESSIBILITY TO WORK APPS FROM THE PHONE"
        if (snapshot.apps.list.isEmpty() || snapshot.apps.notice != notice) {
            scope.launch(Dispatchers.IO) {
                val list = apps.list()
                withContext(Dispatchers.Main) { snapshot = snapshot.copy(apps = snapshot.apps.copy(list = list, notice = notice)) }
            }
        }
    }

    fun appIcon(packageName: String) = apps.icon(packageName)

    private fun launchApp(entry: HudSnapshot.AppEntry) {
        val display = GlassesPresenter.shownDisplay ?: return
        val frame = layout.appsFrame ?: return
        val content = AppsLayout.content(frame.size).translate(frame.topLeft)
        if (apps.launch(entry.packageName, display, apps.mapping(display).rect(content))) {
            snapshot = snapshot.copy(apps = snapshot.apps.copy(running = entry))
        }
    }

    private fun closeApp() {
        if (keyboardTarget == KeyboardTarget.apps) endTyping()
        snapshot = snapshot.copy(apps = snapshot.apps.copy(running = null))
        GlassesPresenter.raise()
    }

    private fun appsClick(target: AppsLayout.Target, p: Offset, right: Boolean) {
        val frame = layout.appsFrame ?: return
        val a = snapshot.apps
        when (target) {
            AppsLayout.Target.home, AppsLayout.Target.close -> if (a.running != null) closeApp()
            AppsLayout.Target.back -> if (a.running != null) HudAccessibility.instance?.back()
            AppsLayout.Target.content -> {
                if (a.running == null) {
                    AppsLayout.app(p, frame.size, a.scrollRow, a.list.size)?.let { launchApp(a.list[it]) }
                    return
                }
                val service = HudAccessibility.instance ?: return
                val display = GlassesPresenter.shownDisplay ?: return
                val at = apps.mapping(display).pixels(p + frame.topLeft)
                service.tap(display.displayId, at, long = right)
                // A text field took the tap: the keyboard comes up for it.
                main.postDelayed({ if (service.focused(display.displayId) != null && keyboardTarget == null) beginAppTyping() }, 400)
            }
        }
    }

    private fun appsScrolled(ticks: Int, p: Offset) {
        val frame = layout.appsFrame ?: return
        val a = snapshot.apps
        if (a.running == null) {
            snapshot = snapshot.copy(apps = a.copy(scrollRow = (a.scrollRow + ticks.coerceIn(-1, 1)).coerceIn(0, AppsLayout.maxRow(a.list.size, frame.size))))
            return
        }
        val service = HudAccessibility.instance ?: return
        val display = GlassesPresenter.shownDisplay ?: return
        val m = apps.mapping(display)
        val from = m.pixels(p + frame.topLeft)
        service.swipe(display.displayId, from, Offset(from.x, from.y - ticks * 60 * m.scale))
    }

    fun openAccessibilitySettings() = apps.openAccessibilitySettings()
    val appsServiceEnabled get() = apps.serviceEnabled

    // ------------------------------------------------------------------ the remote

    private fun remoteMoved(dx: Int, dy: Int) {
        if (pad != PhonePad.remote) return
        pointer = pointer.moved(dx.toFloat(), dy.toFloat())
        showCursor()
        hover()
    }

    private fun remote(zone: RemoteZone, phase: RemotePhase) {
        when (zone to phase) {
            RemoteZone.click to RemotePhase.began -> {
                // Pressing shakes the phone: the cursor holds still so the click lands where aimed.
                remote.hold(0.18)
                remoteDragTimer?.let(main::removeCallbacks)
                remoteDragTimer = Runnable { remoteDragging = true; remote.release() }.also { main.postDelayed(it, 350) }
            }
            RemoteZone.click to RemotePhase.ended -> {
                remoteDragTimer?.let(main::removeCallbacks)
                if (remoteDragging) remoteDragging = false else { showCursor(); click() }
            }
            RemoteZone.rightClick to RemotePhase.began -> remote.hold(0.18)
            RemoteZone.rightClick to RemotePhase.ended -> { showCursor(); click(right = true) }
            RemoteZone.scroll to RemotePhase.began -> { remote.hold(600.0); momentum.stop() }
            RemoteZone.scroll to RemotePhase.ended -> remote.release()
            RemoteZone.centre to RemotePhase.ended -> {
                pointer = Pointer()
                showCursor()
                hover()
            }
            else -> {}
        }
    }

    /** The remote's scroll strip: a tick for every so many points the thumb slides. */
    fun remoteScroll(ticks: Int) = scroll(ticks)

    private val weatherRetry = Runnable { refreshWeather() }

    /** Every fifteen minutes; every minute while there is no location or no answer yet. */
    fun refreshWeather() {
        main.removeCallbacks(weatherRetry)
        val where = Whereabouts(app)
        scope.launch {
            val location = where.last() ?: where.current()
            if (location == null) { main.postDelayed(weatherRetry, 60_000L); return@launch }
            val place = where.placeName(location)
            val weather = OpenMeteo.weather(location.latitude, location.longitude, place)
            if (weather != null) snapshot = snapshot.copy(weather = weather)
            main.postDelayed(weatherRetry, if (weather != null) 15 * 60_000L else 60_000L)
        }
    }

    // ------------------------------------------------------------------ scenes

    private fun loadScenes() {
        val saved = prefs.getString("scenes", null)?.let {
            runCatching { json.decodeFromString(ListSerializer(HudScene.serializer()), it) }.getOrNull()
        }
        // A new version of the presets replaces what was saved from the old ones.
        val current = prefs.getInt("sceneVersion", 0) == HudScene.VERSION
        if (saved != null && saved.size == HudScene.presets.size && current) scenes = saved
        if (!current) prefs.edit().putInt("sceneVersion", HudScene.VERSION).putInt("scene", 0).remove("scenes").apply()
        sceneIndex = prefs.getInt("scene", 0).coerceIn(0, scenes.size - 1)
        arrangement = scenes[sceneIndex].arrangement
    }

    private fun arrange(next: HudArrangement) {
        arrangement = next
        scenes = scenes.toMutableList().also { it[sceneIndex] = it[sceneIndex].copy(arrangement = next) }
        prefs.edit().putString("scenes", json.encodeToString(ListSerializer(HudScene.serializer()), scenes))
            .putInt("scene", sceneIndex).apply()
        panelsChanged()
    }

    private fun panelsChanged() {
        when (keyboardTarget) {
            KeyboardTarget.address, KeyboardTarget.page -> if (!isOnGlasses(HudPanelKind.browser)) endTyping()
            KeyboardTarget.note -> if (!isOnGlasses(HudPanelKind.note)) endTyping()
            KeyboardTarget.mapSearch -> if (!mapFillsCanvas) endTyping()
            KeyboardTarget.mac -> if (!isOnGlasses(HudPanelKind.mac)) endTyping()
            KeyboardTarget.youtubeSearch -> if (!isOnGlasses(HudPanelKind.youtube)) endTyping()
            KeyboardTarget.apps -> if (!isOnGlasses(HudPanelKind.apps)) endTyping()
            null -> {}
        }
        if (::location.isInitialized) {
            sensorsChanged()
            groundCheck()
            lastSky = 0
        }
    }

    // ------------------------------------------------------------------ the phone's buttons

    fun perform(action: PhoneAction) {
        when (action) {
            PhoneAction.Back -> browser?.back()
            PhoneAction.Forward -> browser?.forward()
            PhoneAction.Reload -> browser?.reload()
            PhoneAction.Home -> browser?.goHome(HomePage.html(favorites))
            PhoneAction.NewTab -> openTab(null)
            PhoneAction.Favorite -> toggleFavorite()
            PhoneAction.Address -> if (keyboardTarget == KeyboardTarget.address) endTyping() else beginAddress()
            PhoneAction.Keyboard -> if (keyboardTarget != null) endTyping() else beginPageTyping()
            PhoneAction.Settings -> showingSettings = true
            PhoneAction.ClearView -> { showAlone(null); clearView = !clearView; panelsChanged() }
            is PhoneAction.TapPanel -> {
                if (solo != null) { showAlone(null); panelsChanged(); return }
                if (clearView) clearView = false
                arrange(arrangement.toggleHidden(action.kind))
            }
            is PhoneAction.Solo -> { clearView = false; showAlone(action.kind); panelsChanged() }
            is PhoneAction.Pad -> { pad = action.pad; sensorsChanged() }
            is PhoneAction.Music -> musicAction(action.action)
            PhoneAction.Captions -> captions.toggle()
            is PhoneAction.YouTube -> youtubeAction(action.action)
            is PhoneAction.Sky -> skyAction(action.action)
            is PhoneAction.Maps -> mapAction(action.action, action.index)
            is PhoneAction.Remote -> remote(action.zone, action.phase)
            is PhoneAction.MacWindow -> desktop.send(DesktopWire.Command.Select(action.id))
            is PhoneAction.Timer -> timerAction(action.action)
            is PhoneAction.Note -> noteAction(action.action)
            is PhoneAction.Place -> arrange(arrangement.place(action.kind, action.spot))
            is PhoneAction.Scene -> switchScene(action.index)
            is PhoneAction.ResetScene -> {
                scenes = scenes.toMutableList().also { it[action.index] = HudScene.presets[action.index] }
                switchScene(action.index)
            }
            is PhoneAction.Layout -> arrange(arrangement.setStrip(action.edge))
            is PhoneAction.EditGlasses -> { if (action.on) endTyping(); editingGlasses = action.on }
            is PhoneAction.SelectTab -> selectTab(action.index)
            is PhoneAction.CloseTab -> closeTab(action.index)
        }
    }

    /** Alone on the glasses, an app with controls brings them to the phone; leaving, the pad returns. */
    private fun showAlone(kind: HudPanelKind?) {
        if (solo == HudPanelKind.youtube && kind != HudPanelKind.youtube)
            snapshot = snapshot.copy(youtube = snapshot.youtube.copy(page = HudSnapshot.YouTube.Page.browse))
        if (kind == HudPanelKind.youtube && snapshot.youtube.hasVideo)
            snapshot = snapshot.copy(youtube = snapshot.youtube.copy(page = HudSnapshot.YouTube.Page.player))
        solo = kind
        if (kind?.hasPhoneControls == true) pad = PhonePad.app
        else if (pad == PhonePad.app) pad = PhonePad.touchpad
        if (::location.isInitialized) sensorsChanged()
    }

    private fun timerAction(action: TimerAction) {
        val now = System.currentTimeMillis()
        timer = when (action) {
            TimerAction.Toggle -> timer.toggle(now)
            TimerAction.Reset -> timer.reset()
            is TimerAction.Set -> timer.set(action.minutes)
            is TimerAction.Add -> timer.add(action.minutes)
        }
        prefs.edit().putInt("timerSeconds", timer.setSeconds).apply()
        snapshot = snapshot.copy(timer = timer.reading(now))
    }

    private fun noteAction(action: NoteAction) {
        when (action) {
            NoteAction.Write -> if (keyboardTarget == KeyboardTarget.note) endTyping() else beginNote()
            NoteAction.Clear -> {
                snapshot = snapshot.copy(note = snapshot.note.copy(text = "", scroll = 0f))
                if (keyboardTarget == KeyboardTarget.note) draft = ""
                prefs.edit().putString("note", "").apply()
            }
            is NoteAction.Scroll -> snapshot = snapshot.copy(note = snapshot.note.copy(
                scroll = if (action.by == Float.NEGATIVE_INFINITY) 0f else maxOf(snapshot.note.scroll + action.by, 0f)))
        }
    }

    private fun switchScene(index: Int) {
        showAlone(null)
        clearView = false
        sceneIndex = index
        arrange(scenes[index].arrangement)
    }

    // ------------------------------------------------------------------ tabs

    private fun makeTab(): WebTab? {
        val context = glassesContext ?: return null
        return WebTab(context) { tab -> if (tab === browser) browserChanged() else syncTabs() }
    }

    fun openTab(url: String?) {
        if (tabs.size >= BrowserMetrics.MAX_TABS) { url?.let { browser?.load(it) }; return }
        val tab = makeTab() ?: return
        if (keyboardTarget != null) endTyping()
        tabs.add(tab)
        activeTab = tabs.size - 1
        if (url != null) tab.load(url) else tab.goHome(HomePage.html(favorites))
        browserChanged()
    }

    private fun selectTab(index: Int) {
        if (index !in tabs.indices || index == activeTab) return
        if (keyboardTarget != null) endTyping()
        activeTab = index
        browserChanged()
    }

    private fun closeTab(index: Int) {
        if (index !in tabs.indices) return
        if (keyboardTarget != null) endTyping()
        tabs.removeAt(index).also { it.detach(); it.view.destroy() }
        if (tabs.isEmpty()) { activeTab = 0; openTab(null); return }
        if (index < activeTab || activeTab >= tabs.size) activeTab = maxOf(activeTab - 1, 0)
        browserChanged()
    }

    private fun toggleFavorite() {
        val s = browser?.state ?: return
        if (s.isHome) return
        favorites = if (favorites.any { it.url == s.address }) favorites.filter { it.url != s.address }
        else favorites + HomePage.Favorite(s.title.ifEmpty { s.url }.take(40), s.address)
        prefs.edit().putString("favorites", json.encodeToString(ListSerializer(HomePage.Favorite.serializer()), favorites)).apply()
        browserChanged()
        // Open start pages show the change.
        tabs.filter { it.state.isHome }.forEach { it.goHome(HomePage.html(favorites)) }
    }

    private fun tabTitles() = tabs.map { t ->
        val s = t.state
        when { s.isHome -> "New Tab"; s.title.isNotEmpty() -> s.title; s.url.isNotEmpty() -> s.url; else -> "Loading" }
    }

    private fun syncTabs() { snapshot = snapshot.copy(browser = snapshot.browser.copy(tabs = tabTitles(), activeTab = activeTab)) }

    private fun browserChanged() {
        val s = browser?.state ?: WebTab.State()
        snapshot = snapshot.copy(browser = snapshot.browser.copy(
            url = if (keyboardTarget == KeyboardTarget.address) snapshot.browser.url else s.url,
            title = s.title, canGoBack = s.canGoBack, canGoForward = s.canGoForward, loading = s.loading,
            tabs = tabTitles(), activeTab = activeTab,
            isHome = s.isHome, isFavorite = !s.isHome && favorites.any { it.url == s.address },
        ))
    }

    // ------------------------------------------------------------------ the pad

    fun gesture(event: GestureEvent) {
        when (event) {
            is GestureEvent.Move -> {
                pointer = pointer.moved(Pointer.scale(event.dx) * trackpadSpeed, Pointer.scale(event.dy) * trackpadSpeed)
                showCursor()
                hover()
            }
            GestureEvent.TapClick -> { showCursor(); click() }
            GestureEvent.RightClick -> { showCursor(); click(right = true) }
            is GestureEvent.Scroll -> { momentum.stop(); scroll(event.vScroll) }
            is GestureEvent.ScrollFling -> momentum.startFling(event.velocityY, event.velocityX)
            is GestureEvent.Click, is GestureEvent.Pinch, GestureEvent.DoubleTapDragStart, GestureEvent.DragEnd -> {}
        }
    }

    private fun showCursor() {
        snapshot = snapshot.copy(cursor = pointer.position)
        cursorHide?.let(main::removeCallbacks)
        // Left lying on the glasses it sits over whatever the wearer looks at: it goes after a minute.
        cursorHide = Runnable { snapshot = snapshot.copy(cursor = null) }.also { main.postDelayed(it, 60_000L) }
    }

    private fun hover() {
        val now = System.currentTimeMillis()
        if (solo == HudPanelKind.youtube && snapshot.youtube.page == HudSnapshot.YouTube.Page.player) hideCursorWhileWatching()
        if (now - lastHover < 50) return
        when (val hit = layout.hitTest(pointer.position)) {
            is GlassesHit.Page -> { lastHover = now; browser?.hover(inPage(hit.point), layout.browserFrame?.width ?: 0f) }
            is GlassesHit.Mac -> { lastHover = now; desktop.send(DesktopWire.Command.Move(hit.point.x.toDouble(), hit.point.y.toDouble())) }
            else -> {}
        }
    }

    private fun click(right: Boolean = false) {
        when (val hit = layout.hitTest(pointer.position)) {
            GlassesHit.Back -> browser?.back()
            GlassesHit.Forward -> browser?.forward()
            GlassesHit.Reload -> browser?.reload()
            GlassesHit.NewTab -> openTab(null)
            GlassesHit.Address -> beginAddress()
            is GlassesHit.SelectTab -> selectTab(hit.index)
            is GlassesHit.CloseTab -> closeTab(hit.index)
            is GlassesHit.Page -> {
                if (keyboardTarget == KeyboardTarget.address || keyboardTarget == KeyboardTarget.note) endTyping()
                val tab = browser ?: return
                tab.click(inPage(hit.point), layout.browserFrame?.width ?: 0f, right)
                if (!right) main.postDelayed({ tab.focusTakesText { if (it) beginPageTyping() } }, 120)
            }
            is GlassesHit.Widget -> widgetClick(hit.kind, hit.point, hit.size, right)
            is GlassesHit.Mac -> {
                if (keyboardTarget != null && keyboardTarget != KeyboardTarget.mac) endTyping()
                desktop.send(DesktopWire.Command.Click(hit.point.x.toDouble(), hit.point.y.toDouble(), if (right) 1 else 0))
                if (!right && keyboardTarget == null && snapshot.desktop.connected) beginMacTyping()
            }
            is GlassesHit.Apps -> appsClick(hit.target, hit.point, right)
            GlassesHit.None -> {}
        }
    }

    private fun widgetClick(kind: HudPanelKind, p: Offset, size: androidx.compose.ui.geometry.Size, right: Boolean) {
        val alone = solo == kind
        when (kind) {
            HudPanelKind.note -> if (keyboardTarget == KeyboardTarget.note) endTyping() else beginNote()
            HudPanelKind.clock -> if (alone && ClockAppLayout.timerCard.contains(p)) {
                timer = if (right) timer.reset() else timer.toggle(System.currentTimeMillis())
                snapshot = snapshot.copy(timer = timer.reading(System.currentTimeMillis()))
            }
            HudPanelKind.music -> when (MusicLayout.control(p, size, large = alone)) {
                MusicLayout.Control.previous -> music.previous()
                MusicLayout.Control.playPause -> music.playPause()
                MusicLayout.Control.next -> music.next()
                null -> {}
            }
            HudPanelKind.captions -> if (captions.allowed) captions.toggle() else showingSettings = true
            HudPanelKind.youtube -> {
                if (alone && right && snapshot.youtube.page == HudSnapshot.YouTube.Page.player)
                    youtubeAction(YouTubeAction.Page(HudSnapshot.YouTube.Page.browse))
                else if (!right) youtubeClick(p, alone)
            }
            HudPanelKind.map -> if (alone) {
                val canvas = p + GlassesLayout.safeFrame.topLeft
                val hit = MapsLayout(snapshot.maps.results.size, snapshot.maps.navigation != null).hitTest(canvas)
                mapAction(hit.target, hit.index)
            }
            HudPanelKind.sky -> if (alone) {
                if (right) skyAction(SkyAction.Recentre) else skyClick(p + GlassesLayout.safeFrame.topLeft)
            }
            else -> {}
        }
    }

    private fun scroll(ticks: Int) {
        if (ticks == 0) return
        if (solo == HudPanelKind.note && !clearView) {
            snapshot = snapshot.copy(note = snapshot.note.copy(scroll = maxOf(snapshot.note.scroll + ticks * 40f, 0f)))
            return
        }
        // In the Maps app, scrolling zooms: down to see more, up to see closer.
        if (mapFillsCanvas) return zoomMap(1.1.pow(ticks))
        if (solo == HudPanelKind.sky && !clearView) { skyAction(SkyAction.Zoom(1.08.pow(ticks))); return }
        when (val hit = layout.hitTest(pointer.position)) {
            is GlassesHit.Mac -> {
                // A Mac wheel's positive is up; a tick's is down the page.
                desktop.send(DesktopWire.Command.Scroll(hit.point.x.toDouble(), hit.point.y.toDouble(), 0.0, (-ticks * 48).toDouble()))
                return
            }
            is GlassesHit.Apps -> { appsScrolled(ticks, hit.point); return }
            is GlassesHit.Widget -> when (hit.kind) {
                HudPanelKind.clock -> {
                    // The wheel sets the timer: up for more.
                    if (solo == HudPanelKind.clock && ClockAppLayout.timerCard.contains(hit.point)) {
                        timer = timer.adjust(-ticks)
                        prefs.edit().putInt("timerSeconds", timer.setSeconds).apply()
                        snapshot = snapshot.copy(timer = timer.reading(System.currentTimeMillis()))
                    }
                    return
                }
                HudPanelKind.youtube -> { youtubeScrolled(ticks, solo == HudPanelKind.youtube); return }
                else -> if (solo != null) return
            }
            else -> {}
        }
        val frame = layout.browserFrame ?: return
        val hit = layout.hitTest(pointer.position)
        val point = (hit as? GlassesHit.Page)?.point ?: Offset(frame.width / 2, frame.height / 2)
        browser?.scroll(ticks, inPage(point), frame.width)
    }

    /** Panel points to the page's: below the bar, unless the page is fullscreen. */
    private fun inPage(p: Offset) =
        if (layout.fullscreen) p else Offset(p.x, maxOf(p.y - com.thehud.core.BrowserMetrics.contentTopInset, 0f))

    // ------------------------------------------------------------------ the keyboard

    private const val SENTINEL = "​"

    private fun beginAddress() {
        keyboardTarget = KeyboardTarget.address
        draft = ""
        snapshot = snapshot.copy(browser = snapshot.browser.copy(url = "", isEditingAddress = true))
    }

    private fun beginPageTyping() {
        if (keyboardTarget == KeyboardTarget.address) snapshot = snapshot.copy(browser = snapshot.browser.copy(isEditingAddress = false))
        keyboardTarget = KeyboardTarget.page
        draft = SENTINEL
    }

    private fun beginMapSearch() {
        keyboardTarget = KeyboardTarget.mapSearch
        draft = snapshot.maps.query
        snapshot = snapshot.copy(maps = snapshot.maps.copy(isEditing = true))
    }

    private fun beginYouTubeSearch() {
        keyboardTarget = KeyboardTarget.youtubeSearch
        draft = snapshot.youtube.query
        snapshot = snapshot.copy(youtube = snapshot.youtube.copy(isEditingQuery = true))
    }

    private fun beginMacTyping() {
        keyboardTarget = KeyboardTarget.mac
        draft = SENTINEL
    }

    private fun beginAppTyping() {
        val display = GlassesPresenter.shownDisplay ?: return
        keyboardTarget = KeyboardTarget.apps
        draft = HudAccessibility.instance?.text(display.displayId) ?: ""
    }

    private fun beginNote() {
        keyboardTarget = KeyboardTarget.note
        draft = snapshot.note.text
        snapshot = snapshot.copy(note = snapshot.note.copy(isEditing = true))
    }

    fun endTyping() {
        when (keyboardTarget) {
            KeyboardTarget.note -> {
                snapshot = snapshot.copy(note = snapshot.note.copy(isEditing = false))
                prefs.edit().putString("note", snapshot.note.text).apply()
            }
            KeyboardTarget.address -> snapshot = snapshot.copy(browser = snapshot.browser.copy(
                isEditingAddress = false, url = browser?.state?.url.orEmpty()))
            KeyboardTarget.mapSearch -> snapshot = snapshot.copy(maps = snapshot.maps.copy(isEditing = false))
            KeyboardTarget.youtubeSearch -> snapshot = snapshot.copy(youtube = snapshot.youtube.copy(isEditingQuery = false))
            else -> {}
        }
        keyboardTarget = null
        draft = ""
    }

    fun draftChanged(new: String) {
        when (keyboardTarget) {
            KeyboardTarget.address -> { draft = new; snapshot = snapshot.copy(browser = snapshot.browser.copy(url = new)) }
            KeyboardTarget.note -> { draft = new; snapshot = snapshot.copy(note = snapshot.note.copy(text = new)) }
            KeyboardTarget.page, KeyboardTarget.mac -> {
                val old = draft.removePrefix(SENTINEL)
                if (new.startsWith(SENTINEL)) {
                    send(old, new.removePrefix(SENTINEL)); draft = new
                } else {
                    // The sentinel went: one backspace past everything typed here.
                    send(old, new); deleteBackward(1); draft = SENTINEL + new
                }
            }
            KeyboardTarget.mapSearch -> {
                draft = new
                snapshot = snapshot.copy(maps = snapshot.maps.copy(query = new))
                search(new)
            }
            KeyboardTarget.youtubeSearch -> {
                draft = new
                snapshot = snapshot.copy(youtube = snapshot.youtube.copy(query = new))
                searchYouTube(new)
            }
            KeyboardTarget.apps -> {
                draft = new
                GlassesPresenter.shownDisplay?.let { HudAccessibility.instance?.setText(it.displayId, new) }
            }
            null -> draft = new
        }
    }

    private fun send(old: String, new: String) {
        val common = old.commonPrefixWith(new).length
        deleteBackward(old.length - common)
        val insert = new.substring(common)
        if (insert.isEmpty()) return
        if (keyboardTarget == KeyboardTarget.mac) desktop.send(DesktopWire.Command.Text(insert)) else browser?.insert(insert)
    }

    private fun deleteBackward(count: Int) {
        if (count <= 0) return
        if (keyboardTarget == KeyboardTarget.mac) repeat(count) { desktop.send(DesktopWire.Command.Key("delete")) }
        else browser?.deleteBackward(count)
    }

    fun submitTyping() {
        when (keyboardTarget) {
            KeyboardTarget.address -> { AddressInput.url(draft)?.let { browser?.load(it) }; endTyping() }
            KeyboardTarget.page -> { browser?.submit(); endTyping() }
            KeyboardTarget.note -> endTyping()
            // On the Mac, Return is a key like any other: the keyboard stays up.
            KeyboardTarget.mac -> { desktop.send(DesktopWire.Command.Key("return")); draft = SENTINEL }
            KeyboardTarget.mapSearch -> if (searchResults.isNotEmpty()) route(0) else endTyping()
            KeyboardTarget.youtubeSearch -> { searchYouTube(draft, now = true); endTyping() }
            KeyboardTarget.apps -> { GlassesPresenter.shownDisplay?.let { HudAccessibility.instance?.enter(it.displayId) }; endTyping() }
            null -> {}
        }
    }
}
