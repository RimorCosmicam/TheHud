package com.thehud

import android.content.Context
import android.util.Log
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.ui.geometry.Offset
import android.graphics.Bitmap
import android.view.TextureView
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.thehud.apps.GlassesOverlayService
import com.thehud.core.BrowserMetrics
import com.thehud.core.ClockAppLayout
import com.thehud.core.MapsLayout
import com.thehud.core.MusicLayout
import com.thehud.core.PhotosLayout
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
import com.thehud.data.PhotosProvider
import com.thehud.data.LatLon
import com.thehud.data.LocationProvider
import com.thehud.data.MapGround
import com.thehud.data.MapsService
import com.thehud.data.MusicProvider
import com.thehud.data.NavigationTracker
import com.thehud.data.OverheadProvider
import com.thehud.data.RoutePlan
import com.thehud.data.WorldClocks
import com.thehud.connect.RemoteServer
import com.thehud.connect.RemoteWire
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

/** Host mode: the iPhone's YouTube video, played here in the box it gives, in step with its time. */
data class HostVideo(val id: String, val time: Double, val playing: Boolean, val ad: Boolean,
                     val box: androidx.compose.ui.geometry.Rect?, val corner: Float)

/** Host mode: what a film of the iPhone's glasses cannot hold. */
data class HostOverlay(val cursor: Offset? = null, val video: HostVideo? = null,
                       val mac: androidx.compose.ui.geometry.Rect? = null)

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
    /** The APP picker: this app in the centre. */
    data class Centre(val kind: HudPanelKind) : PhoneAction
    data class Prompter(val action: PrompterAction) : PhoneAction
    data class Photos(val action: PhotosAction) : PhoneAction
}

enum class PrompterAction { Toggle, Faster, Slower, Restart }

sealed interface PhotosAction {
    /** The next photo (positive) or an earlier one: the one shown, or the gallery's pick. */
    data class Step(val by: Int) : PhotosAction
    /** Fullscreen: the picked photo alone, or back to the grid. */
    data object Open : PhotosAction
}

enum class KeyboardTarget { address, page, note, mapSearch, mac, youtubeSearch }

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
    HudPanelKind.captions, HudPanelKind.note, HudPanelKind.youtube, HudPanelKind.map, HudPanelKind.prompter, HudPanelKind.photos)

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

    /** The browser in use: held open on the glasses, or an address being typed. Its buttons and tabs show only then. */
    val browsing: Boolean get() = solo == HudPanelKind.browser || keyboardTarget == KeyboardTarget.address

    /** The phone's own pictures for the glasses: the map's ground and the album art. */
    var mapGround by mutableStateOf<ImageBitmap?>(null)
        private set
    var artwork by mutableStateOf<ImageBitmap?>(null)
        private set
    /** The photo library's pictures on show, by index. */
    var photoImages by mutableStateOf<Map<Int, ImageBitmap>>(emptyMap())
        private set
    /** Where the phone faces, unwrapped, at the sensor's own rate: read only where it is drawn. */
    val heading = androidx.compose.runtime.mutableDoubleStateOf(0.0)
    var youtube: YouTubePlayer? = null
        private set
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

    /** Remote Connect: the paired iPhone working these glasses (its name while it is connected). */
    var remotePeer by mutableStateOf<String?>(null)
    /** Host mode: the paired iPhone runs the apps and this phone only shows its picture on the glasses. */
    var hosted by mutableStateOf(false)
        private set
    var hostOverlay by mutableStateOf(HostOverlay())
        private set
    private var hostVideoId = ""
    private var hostToggledAt = 0L
    private var hostSeekedAt = 0L
    /** The pairing screen, opened by holding settings. */
    var showingConnect by mutableStateOf(false)
    /** What the pairing QR code says; changes with a new code. */
    var connectLink by mutableStateOf("")
    private lateinit var connect: RemoteServer
        private set

    private lateinit var location: LocationProvider
    private lateinit var calendar: CalendarProvider
    private lateinit var photos: PhotosProvider
    private var photoScroll = 0
    private var lastSlide = 0L
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
            snapshot.desktop.aspect, snapshot.browser.isEditingAddress)

    /** The app whose controls the pad can show: the fullscreen one, or else the centre's. */
    val padApp: HudPanelKind?
        get() = when {
            clearView -> null
            solo != null -> solo?.takeIf { it.hasPhoneControls }
            else -> arrangement.centre?.kind?.takeIf { it.hasPhoneControls && arrangement.isShown(it) }
        }

    fun isOnGlasses(kind: HudPanelKind): Boolean =
        if (clearView || hosted) false else solo?.let { it == kind } ?: arrangement.isShown(kind)

    fun start(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        prefs = app.getSharedPreferences("hud", Context.MODE_PRIVATE)
        // Debug builds' pages can be inspected from the Mac's Chrome (chrome://inspect).
        if (app.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0)
            android.webkit.WebView.setWebContentsDebuggingEnabled(true)
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
        location = LocationProvider(app, onHeading = { heading.doubleValue = it }) { minimap, at, _ -> located(minimap, at) }
        calendar = CalendarProvider(app)
        photos = PhotosProvider(app, scope) { photosChanged() }
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
        startConnect()
    }

    // ------------------------------------------------------------------ Remote Connect

    private fun startConnect() {
        connect = RemoteServer(app)
        connect.onPeer = { name, hosting ->
            remotePeer = name
            // Hosting, this phone's own apps rest: nothing of theirs is on the glasses.
            val wasHosted = hosted
            hosted = name != null && hosting
            if (hosted != wasHosted) {
                // This phone's own video stops either way: hosting, the iPhone's plays here instead.
                if (youtube?.state?.hasVideo == true) youtube?.stop()
                hostVideoId = ""
                hostOverlay = HostOverlay()
                if (hosted) endTyping()
                panelsChanged()
            }
            // The iPhone points now: this phone's own aim stops.
            sensorsChanged()
            if (name != null) {
                // Paired: the code has done its job.
                showingConnect = false
                if (!hosting) connect.send(RemoteWire.state(this))
            }
        }
        connect.onMessage = { remoteMessage(it) }
        connect.onOverlay = { hostOverlayArrived(it) }
        connect.start()
        // The state as the iPhone draws it, sent when it changes, at most ten times a second.
        scope.launch {
            snapshotFlow { if (remotePeer != null && !hosted) RemoteWire.state(this@HudController) else "" }
                .distinctUntilChanged()
                .collect { line ->
                    if (line.isNotEmpty()) connect.send(line)
                    delay(100)
                }
        }
    }

    private fun hostOverlayArrived(o: org.json.JSONObject) {
        if (!hosted) return
        fun rect(a: org.json.JSONArray?) = a?.takeIf { it.length() == 4 }?.let {
            androidx.compose.ui.geometry.Rect(Offset(it.optDouble(0).toFloat(), it.optDouble(1).toFloat()),
                androidx.compose.ui.geometry.Size(it.optDouble(2).toFloat(), it.optDouble(3).toFloat()))
        }
        val cursor = o.optJSONArray("cursor")?.let { Offset(it.optDouble(0).toFloat(), it.optDouble(1).toFloat()) }
        val video = o.optJSONObject("video")?.let { v ->
            HostVideo(v.optString("id"), v.optDouble("t", 0.0), v.optBoolean("playing"), v.optBoolean("ad"),
                rect(v.optJSONArray("box")), v.optDouble("corner", 0.0).toFloat())
        }
        hostOverlay = HostOverlay(cursor, video, rect(o.optJSONArray("mac")))
        syncHostVideo(video)
    }

    /** The iPhone's video, here: the same one, at its time, playing or paused as it is there. */
    private fun syncHostVideo(v: HostVideo?) {
        val player = youtube ?: return
        if (v == null || v.id.isEmpty()) {
            if (hostVideoId.isNotEmpty()) { player.stop(); hostVideoId = "" }
            return
        }
        val now = System.currentTimeMillis()
        if (v.id != hostVideoId) {
            hostVideoId = v.id
            player.play(v.id)
            hostSeekedAt = now; hostToggledAt = now
            return
        }
        val s = player.state
        // Ads come and go on each phone by themselves: only the film itself is kept in step.
        if (!s.hasVideo || s.isAd || v.ad) return
        // Both players report once a second, so only a real gap is closed, and not twice running.
        if (now - hostSeekedAt > 3000 && kotlin.math.abs(s.elapsed - v.time) > 2.5) { player.seek(v.time - s.elapsed); hostSeekedAt = now }
        if (s.isPlaying != v.playing && now - hostToggledAt > 2500) { player.togglePlay(); hostToggledAt = now }
    }

    /** Opens the pairing screen with a fresh look at the address, which may have changed. */
    fun showConnect() {
        connectLink = connect.pairingLink()
        showingConnect = true
    }

    /** Host mode: the iPhone's picture goes to this view on the glasses. */
    fun attachHost(view: TextureView) = connect.hostPicture.attach(view)

    /** Ends Remote Connect for now; the iPhone comes back when it reconnects. */
    fun dropRemote() = connect.drop()

    /** A new key: whoever was paired has to scan again. */
    fun newConnectCode() {
        connect.forget()
        connectLink = connect.pairingLink()
    }

    private fun remoteMessage(o: org.json.JSONObject) {
        when (o.optString("t")) {
            "action" -> RemoteWire.action(o, this)?.let { perform(it) }
            // The iPhone's moves are already in the glasses' points, as it would apply them itself.
            "gesture" -> when (o.optString("g")) {
                "move" -> aimed(o.optInt("dx").toFloat(), o.optInt("dy").toFloat())
                "centre" -> { pointer = Pointer(); showCursor(); hover() }
                else -> RemoteWire.gesture(o)?.let { gesture(it) }
            }
            "draft" -> draftChanged(o.optString("text"))
            "submit" -> submitTyping()
            "endTyping" -> endTyping()
        }
    }

    /** After a permission is granted, or settings come back: start whatever can now start. */
    fun startProviders() {
        activity.start()
        music.start()
        photos.start()
        photosChanged()
        sensorsChanged()
        lastCalendar = 0
        settingsVersion++
    }

    /** Location and the Mac run only while something on the glasses needs them. */
    private fun sensorsChanged() {
        val needsLocation = isOnGlasses(HudPanelKind.map) || isOnGlasses(HudPanelKind.sky) || tracker != null
        if (needsLocation) location.start() else location.stop()
        if (isOnGlasses(HudPanelKind.mac)) desktop.start() else desktop.stop()
        if (pad == PhonePad.remote && remotePeer == null) remote.start() else remote.stop()
        if (isOnGlasses(HudPanelKind.youtube)) refreshYouTube(snapshot.youtube.tab)
        else if (!hosted && youtube?.state?.hasVideo == true) {
            youtube?.stop()
            snapshot = snapshot.copy(youtube = snapshot.youtube.copy(hasVideo = false, isPlaying = false, page = HudSnapshot.YouTube.Page.browse))
        }
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
        agendaTick(now, is24)
        slideshow()
        music.tick()
        captions.tick()
        skyTick()
        main.postDelayed(::tick, 1000L - System.currentTimeMillis() % 1000L)
    }

    private var lastAgendaMinute = -1L

    /** The calendar app's day and month, read once a minute while it is on the glasses. */
    private fun agendaTick(now: Date, is24: Boolean) {
        val minute = now.time / 60_000
        if (minute == lastAgendaMinute || !isOnGlasses(HudPanelKind.calendar)) return
        lastAgendaMinute = minute
        val at = now.time
        scope.launch {
            val agenda = withContext(Dispatchers.IO) { calendar.agendaApp(at, is24) }
            snapshot = snapshot.copy(agenda = agenda)
        }
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
    private val mapInCentre get() = solo == null && !clearView && arrangement.centre?.kind == HudPanelKind.map && arrangement.isShown(HudPanelKind.map)

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
        return if (mapFillsCanvas || mapInCentre) {
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
        val pr = SkyProjection(com.thehud.glasses.skyFacing(heading.doubleValue, v), v.fov, v.tilt)
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
        if (state.ended && !hosted) youtubeNext()
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

    private fun youtubeClick(p: Offset, size: androidx.compose.ui.geometry.Size, alone: Boolean) {
        val y = snapshot.youtube
        if (!alone) { if (y.hasVideo) youtube?.togglePlay() else perform(PhoneAction.Solo(HudPanelKind.youtube)); return }
        when (val t = YouTubeAppLayout.target(p, y, size)) {
            is YouTubeAppLayout.Target.Tab -> youtubeAction(YouTubeAction.Tab(t.tab))
            YouTubeAppLayout.Target.NowPlaying -> youtubeAction(YouTubeAction.Page(HudSnapshot.YouTube.Page.player))
            is YouTubeAppLayout.Target.Card -> y.list(y.tab).getOrNull(t.index)?.let(::playYouTube)
            YouTubeAppLayout.Target.Video -> { youtube?.togglePlay(); hideCursorWhileWatching() }
            null -> {}
        }
    }

    private fun youtubeScrolled(ticks: Int, alone: Boolean, size: androidx.compose.ui.geometry.Size = com.thehud.core.fullAppSize) {
        val y = snapshot.youtube
        val watching = !alone || y.page == HudSnapshot.YouTube.Page.player
        youtubeScrollTicks += ticks
        // Three ticks a step: a row of videos while browsing, five seconds while watching.
        while (kotlin.math.abs(youtubeScrollTicks) >= 3) {
            val step = if (youtubeScrollTicks > 0) 1 else -1
            youtubeScrollTicks -= step * 3
            if (watching) { if (y.hasVideo && !y.isLive) youtube?.seek(step * 5.0) }
            else snapshot = snapshot.copy(youtube = snapshot.youtube.copy(
                scrollRow = (snapshot.youtube.scrollRow + step).coerceIn(0, YouTubeAppLayout.maxRow(y.list(y.tab).size, size))))
        }
    }

    // ------------------------------------------------------------------ the glasses over DeX

    fun openAccessibilitySettings() = GlassesOverlayService.openSettings(app)
    /** TheHud's accessibility service is on: the glasses are drawn above DeX's taskbar. */
    val overlayServiceEnabled get() = GlassesOverlayService.enabled(app)

    // ------------------------------------------------------------------ the remote

    /** The iPhone pointed, or slid its thumb: the cursor moves as it would there. */
    private fun aimed(dx: Float, dy: Float) {
        pointer = pointer.moved(dx, dy)
        showCursor()
        hover()
    }

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
        val before = padApp
        arrangement = next
        if (padApp != before) padFollows()
        scenes = scenes.toMutableList().also { it[sceneIndex] = it[sceneIndex].copy(arrangement = next) }
        prefs.edit().putString("scenes", json.encodeToString(ListSerializer(HudScene.serializer()), scenes))
            .putInt("scene", sceneIndex).apply()
        panelsChanged()
    }

    private fun panelsChanged() {
        when (keyboardTarget) {
            KeyboardTarget.address, KeyboardTarget.page -> if (!isOnGlasses(HudPanelKind.browser)) endTyping()
            KeyboardTarget.note -> if (!isOnGlasses(HudPanelKind.note) && !isOnGlasses(HudPanelKind.prompter)) endTyping()
            KeyboardTarget.mapSearch -> if (!mapFillsCanvas) endTyping()
            KeyboardTarget.mac -> if (!isOnGlasses(HudPanelKind.mac)) endTyping()
            KeyboardTarget.youtubeSearch -> if (!isOnGlasses(HudPanelKind.youtube)) endTyping()
            null -> {}
        }
        if (::location.isInitialized) {
            sensorsChanged()
            groundCheck()
            lastSky = 0
            lastAgendaMinute = -1
            photosChanged()
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
            PhoneAction.ClearView -> { showAlone(null); clearView = !clearView; padFollows(); panelsChanged() }
            is PhoneAction.TapPanel -> {
                if (solo != null) { showAlone(null); panelsChanged(); return }
                if (clearView) clearView = false
                arrange(arrangement.toggleHidden(action.kind))
            }
            is PhoneAction.Solo -> { clearView = false; showAlone(action.kind); panelsChanged() }
            is PhoneAction.Centre -> { clearView = false; showAlone(null); arrange(arrangement.setCentre(action.kind)) }
            is PhoneAction.Prompter -> prompterAction(action.action)
            is PhoneAction.Photos -> photosAction(action.action)
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
        padFollows()
        if (::location.isInitialized) sensorsChanged()
    }

    /** An app with controls, alone or in the centre, brings them to the phone; when it goes, the pad returns. */
    private fun padFollows() {
        if (padApp != null) pad = PhonePad.app
        else if (pad == PhonePad.app) pad = PhonePad.touchpad
    }

    // ------------------------------------------------------------------ teleprompter

    /** Every change starts again from where it is now, so the glasses' smooth scrolling never jumps. */
    private fun prompterAction(action: PrompterAction) {
        val now = System.currentTimeMillis()
        val p = snapshot.prompter
        val anchored = p.copy(anchorOffset = p.offset(now), anchorTime = now)
        val next = when (action) {
            PrompterAction.Toggle -> anchored.copy(isRunning = !p.isRunning)
            PrompterAction.Faster -> anchored.copy(speed = minOf(p.speed + 30, HudSnapshot.Prompter.MAX_SPEED))
            PrompterAction.Slower -> anchored.copy(speed = maxOf(p.speed - 30, HudSnapshot.Prompter.MIN_SPEED))
            PrompterAction.Restart -> anchored.copy(anchorOffset = 0f)
        }
        snapshot = snapshot.copy(prompter = next)
    }

    /** The wheel moves the words by hand, running or not. */
    private fun prompterNudge(ticks: Int) {
        val now = System.currentTimeMillis()
        val p = snapshot.prompter
        snapshot = snapshot.copy(prompter = p.copy(anchorOffset = maxOf(p.offset(now) + ticks * 24f, 0f), anchorTime = now))
    }

    // ------------------------------------------------------------------ photos

    /** The library's count and the caption, and the pictures on show loaded: the gallery's page held up alone, otherwise the one photo. */
    private fun photosChanged() {
        if (!::photos.isInitialized) return
        var p = snapshot.photos
        val last = maxOf(photos.count - 1, 0)
        p = p.copy(hasAccess = photos.hasAccess, count = photos.count, current = minOf(p.current, last),
            selected = minOf(p.selected, last), scrollRow = minOf(p.scrollRow, PhotosLayout.maxRow(photos.count)))
        val gallery = solo == HudPanelKind.photos && !clearView
        p = p.copy(caption = photos.caption(if (gallery) p.selected else p.current))
        if (p != snapshot.photos) snapshot = snapshot.copy(photos = p)
        if (!isOnGlasses(HudPanelKind.photos)) {
            photos.show(emptyList(), null)
            if (photoImages.isNotEmpty()) photoImages = emptyMap()
            return
        }
        val perPage = PhotosLayout.COLUMNS * PhotosLayout.ROWS
        val first = p.scrollRow * PhotosLayout.COLUMNS
        val page = if (gallery) (first until minOf(first + perPage, p.count)).toList() else emptyList()
        photos.show(page, if (gallery) (if (p.viewing) p.selected else null) else p.current)
        photoImages = photos.images
    }

    private fun photosAction(action: PhotosAction) {
        val p = snapshot.photos
        if (p.count <= 0) return
        when (action) {
            is PhotosAction.Step -> snapshot = snapshot.copy(photos = if (solo == HudPanelKind.photos) {
                val selected = (p.selected + action.by).coerceIn(0, p.count - 1)
                p.copy(selected = selected, scrollRow = PhotosLayout.row(selected, p.scrollRow))
            } else {
                lastSlide = System.currentTimeMillis()
                p.copy(current = ((p.current + action.by) % p.count + p.count) % p.count)
            })
            PhotosAction.Open -> {
                if (solo != HudPanelKind.photos) return
                snapshot = snapshot.copy(photos = p.copy(viewing = !p.viewing))
            }
        }
        photosChanged()
    }

    /** The gallery's wheel: a row at a time, or open, photo to photo. */
    private fun photosScrolled(ticks: Int) {
        photoScroll += ticks
        val notches = photoScroll / 3
        if (notches == 0) return
        photoScroll -= notches * 3
        if (snapshot.photos.viewing) return photosAction(PhotosAction.Step(notches))
        snapshot = snapshot.copy(photos = snapshot.photos.copy(
            scrollRow = (snapshot.photos.scrollRow + notches).coerceIn(0, PhotosLayout.maxRow(snapshot.photos.count))))
        photosChanged()
    }

    /** The widget and the centre show a new photo every few seconds. */
    private fun slideshow() {
        val now = System.currentTimeMillis()
        if (!isOnGlasses(HudPanelKind.photos) || solo == HudPanelKind.photos || snapshot.photos.count <= 1 || now - lastSlide < 8000) return
        lastSlide = now
        snapshot = snapshot.copy(photos = snapshot.photos.copy(current = (snapshot.photos.current + 1) % snapshot.photos.count))
        photosChanged()
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

    // ------------------------------------------------------------------ Google sign-in

    /** Where signing the browser in with the phone's Google account stands, for the settings page. */
    var googleSignIn by mutableStateOf("")
        private set

    /**
     * The phone's own Google account signs the glasses' browser in: Android's account system, with
     * the wearer's consent, hands out a one-time link that sets youtube.com's and google.com's
     * cookies, so no password page (and none of Google's checks of in-app browsers) is involved.
     */
    fun webSignIn(activity: android.app.Activity, name: String) {
        val accounts = android.accounts.AccountManager.get(activity)
        val account = android.accounts.Account(name, "com.google")
        val type = "weblogin:service=youtube&continue=" + java.net.URLEncoder.encode("https://www.youtube.com/", "UTF-8")
        googleSignIn = "ASKING"
        accounts.getAuthToken(account, type, null, activity, { future ->
            val link = runCatching { future.result.getString(android.accounts.AccountManager.KEY_AUTHTOKEN) }
                .onFailure { Log.w("HudSignIn", "no sign-in link: ${it.javaClass.simpleName}: ${it.message}") }
                .getOrNull()
            if (link == null || !link.startsWith("https://")) {
                googleSignIn = "REFUSED"
                return@getAuthToken
            }
            // The link works once: forget it, so another sign-in asks for a fresh one.
            accounts.invalidateAuthToken("com.google", link)
            val tab = browser
            if (tab != null) tab.load(link) else openTab(link)
            googleSignIn = "SIGNED IN"
            main.postDelayed({
                refreshYouTube(HudSnapshot.YouTube.Tab.home, force = true)
                refreshYouTube(HudSnapshot.YouTube.Tab.subscriptions, force = true)
            }, 6000)
        }, null)
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
        youtubeAccountCheck()
    }

    private var youtubeSignedIn: Boolean? = null

    /**
     * YouTube shares the browser's sign-in, as on the iPhone: one cookie store for both. When
     * someone signs in or out in the browser, the YouTube panel's lists are fetched again at once.
     */
    private fun youtubeAccountCheck() {
        val now = YouTubeData.isSignedIn
        val was = youtubeSignedIn
        youtubeSignedIn = now
        if (was == null || was == now) return
        android.webkit.CookieManager.getInstance().flush()
        refreshYouTube(HudSnapshot.YouTube.Tab.home, force = true)
        refreshYouTube(HudSnapshot.YouTube.Tab.subscriptions, force = true)
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
            is GlassesHit.Widget -> appClick(hit.kind, hit.point, hit.size, large = solo == hit.kind, right = right)
            is GlassesHit.Centre -> appClick(hit.kind, hit.point, hit.size, large = true, right = right)
            is GlassesHit.Mac -> {
                if (keyboardTarget != null && keyboardTarget != KeyboardTarget.mac) endTyping()
                desktop.send(DesktopWire.Command.Click(hit.point.x.toDouble(), hit.point.y.toDouble(), if (right) 1 else 0))
                if (!right && keyboardTarget == null && snapshot.desktop.connected) beginMacTyping()
            }
            GlassesHit.None -> {}
        }
    }

    /** Clicks on apps: as widgets, in the centre, or held up alone (`large` for the last two). */
    private fun appClick(kind: HudPanelKind, p: Offset, size: androidx.compose.ui.geometry.Size, large: Boolean, right: Boolean) {
        val alone = large
        when (kind) {
            HudPanelKind.note -> if (keyboardTarget == KeyboardTarget.note) endTyping() else beginNote()
            HudPanelKind.clock -> if (alone && ClockAppLayout.timerCard(size).contains(p)) {
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
                else if (!right) youtubeClick(p, size, alone)
            }
            HudPanelKind.prompter -> prompterAction(if (right) PrompterAction.Restart else PrompterAction.Toggle)
            HudPanelKind.photos -> if (solo == HudPanelKind.photos) {
                // The gallery: a click picks a photo, and on the picked one opens it; open, a click goes back to the grid.
                val ph = snapshot.photos
                if (ph.viewing) snapshot = snapshot.copy(photos = ph.copy(viewing = false))
                else if (!right) PhotosLayout.photo(p, size, ph)?.let { i ->
                    snapshot = snapshot.copy(photos = ph.copy(selected = i, viewing = i == ph.selected))
                }
                photosChanged()
            } else if (!right) photosAction(PhotosAction.Step(1))
            HudPanelKind.map -> if (solo == HudPanelKind.map) {
                val canvas = p + GlassesLayout.safeFrame.topLeft
                val hit = MapsLayout(snapshot.maps.results.size, snapshot.maps.navigation != null).hitTest(canvas)
                mapAction(hit.target, hit.index)
            }
            HudPanelKind.sky -> if (solo == HudPanelKind.sky) {
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
            is GlassesHit.Centre -> { centreScrolled(hit.kind, ticks, hit.point, hit.size); return }
            is GlassesHit.Widget -> when (hit.kind) {
                HudPanelKind.photos -> { if (solo == HudPanelKind.photos) photosScrolled(ticks); return }
                HudPanelKind.prompter -> { if (solo == HudPanelKind.prompter) prompterNudge(ticks); return }
                HudPanelKind.clock -> {
                    // The wheel sets the timer: up for more.
                    if (solo == HudPanelKind.clock && ClockAppLayout.timerCard.contains(hit.point)) {
                        timer = timer.adjust(-ticks)
                        prefs.edit().putInt("timerSeconds", timer.setSeconds).apply()
                        snapshot = snapshot.copy(timer = timer.reading(System.currentTimeMillis()))
                    }
                    return
                }
                HudPanelKind.youtube -> { youtubeScrolled(ticks, solo == HudPanelKind.youtube, hit.size); return }
                else -> if (solo != null) return
            }
            else -> {}
        }
        val frame = layout.browserFrame ?: return
        val hit = layout.hitTest(pointer.position)
        val point = (hit as? GlassesHit.Page)?.point ?: Offset(frame.width / 2, frame.height / 2)
        browser?.scroll(ticks, inPage(point), frame.width)
    }

    /** The wheel over the app in the centre. */
    private fun centreScrolled(kind: HudPanelKind, ticks: Int, p: Offset, size: androidx.compose.ui.geometry.Size) {
        when (kind) {
            HudPanelKind.clock -> if (ClockAppLayout.timerCard(size).contains(p)) {
                timer = timer.adjust(-ticks)
                prefs.edit().putInt("timerSeconds", timer.setSeconds).apply()
                snapshot = snapshot.copy(timer = timer.reading(System.currentTimeMillis()))
            }
            HudPanelKind.youtube -> youtubeScrolled(ticks, true, size)
            HudPanelKind.note -> snapshot = snapshot.copy(note = snapshot.note.copy(scroll = maxOf(snapshot.note.scroll + ticks * 40f, 0f)))
            HudPanelKind.photos -> {
                photoScroll += ticks
                val notches = photoScroll / 3
                if (notches != 0) { photoScroll -= notches * 3; photosAction(PhotosAction.Step(notches)) }
            }
            HudPanelKind.prompter -> prompterNudge(ticks)
            HudPanelKind.sky -> skyAction(SkyAction.Zoom(1.08.pow(ticks)))
            HudPanelKind.map -> zoomMap(1.1.pow(ticks))
            else -> {}
        }
    }

    /** Panel points to the page's: below the bar, when the bar shows. */
    private fun inPage(p: Offset) =
        if (layout.barFrame == null) p else Offset(p.x, maxOf(p.y - com.thehud.core.BrowserMetrics.contentTopInset, 0f))

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
            null -> {}
        }
    }
}
