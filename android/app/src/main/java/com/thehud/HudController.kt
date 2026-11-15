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
import com.thehud.core.BrowserMetrics
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
}

enum class KeyboardTarget { address, page, note }

/** What the lower half of the cover screen is: the touchpad, or the controls of the app shown alone. */
enum class PhonePad { touchpad, app }

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
val HudPanelKind.hasPhoneControls get() = this == HudPanelKind.clock || this == HudPanelKind.note

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

    private var pointer = Pointer()
    private val momentum by lazy { PhysicsMomentumScroller(scope) { v, _ -> scroll(v) } }
    private var timer = HudTimer()
    private var glassesContext: Context? = null
    private var lastHover = 0L
    private var cursorHide: Runnable? = null

    val layout: GlassesLayout
        get() = GlassesLayout(arrangement, solo, clearView, snapshot.browser.tabs.size, activeTab, snapshot.browser.isFullscreen)

    fun isOnGlasses(kind: HudPanelKind): Boolean =
        if (clearView) false else solo?.let { it == kind } ?: arrangement.isShown(kind)

    fun start(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        prefs = app.getSharedPreferences("hud", Context.MODE_PRIVATE)
        loadScenes()
        prefs.getString("favorites", null)?.let {
            runCatching { json.decodeFromString(ListSerializer(HomePage.Favorite.serializer()), it) }.getOrNull()
        }?.let { favorites = it }
        snapshot = snapshot.copy(note = HudSnapshot.Note(prefs.getString("note", "") ?: ""))
        tick()
        refreshWeather()
    }

    // ------------------------------------------------------------------ the glasses

    /** The glasses' window came up: pages are made in its context, so they lay out at its size. */
    fun glassesAttached(context: Context) {
        glassesContext = context
        glassesConnected = true
        if (tabs.isEmpty()) openTab(null)
    }

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
            nextEvent = null, nextEventTime = null,
        )
        snapshot = snapshot.copy(clock = clock, timer = timer.reading(System.currentTimeMillis()))
        main.postDelayed(::tick, 1000L - System.currentTimeMillis() % 1000L)
    }

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
        if (saved != null && saved.size == HudScene.presets.size) scenes = saved
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
            null -> {}
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
            is PhoneAction.Pad -> pad = action.pad
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
        solo = kind
        pad = if (kind?.hasPhoneControls == true) PhonePad.app else PhonePad.touchpad
    }

    private fun timerAction(action: TimerAction) {
        val now = System.currentTimeMillis()
        timer = when (action) {
            TimerAction.Toggle -> timer.toggle(now)
            TimerAction.Reset -> timer.reset()
            is TimerAction.Set -> timer.set(action.minutes)
            is TimerAction.Add -> timer.add(action.minutes)
        }
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
                pointer = pointer.moved(Pointer.scale(event.dx), Pointer.scale(event.dy))
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
        if (now - lastHover < 50) return
        val hit = layout.hitTest(pointer.position) as? GlassesHit.Page ?: return
        lastHover = now
        browser?.hover(inPage(hit.point), layout.browserFrame?.width ?: 0f)
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
            is GlassesHit.Widget -> widgetClick(hit.kind)
            GlassesHit.None -> {}
        }
    }

    private fun widgetClick(kind: HudPanelKind) {
        when (kind) {
            HudPanelKind.note -> if (keyboardTarget == KeyboardTarget.note) endTyping() else beginNote()
            HudPanelKind.clock -> if (solo == HudPanelKind.clock) {
                timer = timer.toggle(System.currentTimeMillis())
                snapshot = snapshot.copy(timer = timer.reading(System.currentTimeMillis()))
            }
            else -> {}
        }
    }

    private fun scroll(ticks: Int) {
        if (ticks == 0) return
        if (solo == HudPanelKind.note) {
            snapshot = snapshot.copy(note = snapshot.note.copy(scroll = maxOf(snapshot.note.scroll + ticks * 40f, 0f)))
            return
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
            else -> {}
        }
        keyboardTarget = null
        draft = ""
    }

    fun draftChanged(new: String) {
        when (keyboardTarget) {
            KeyboardTarget.address -> { draft = new; snapshot = snapshot.copy(browser = snapshot.browser.copy(url = new)) }
            KeyboardTarget.note -> { draft = new; snapshot = snapshot.copy(note = snapshot.note.copy(text = new)) }
            KeyboardTarget.page -> {
                val old = draft.removePrefix(SENTINEL)
                if (new.startsWith(SENTINEL)) {
                    send(old, new.removePrefix(SENTINEL)); draft = new
                } else {
                    // The sentinel went: one backspace past everything typed here.
                    send(old, new); browser?.deleteBackward(1); draft = SENTINEL + new
                }
            }
            null -> draft = new
        }
    }

    private fun send(old: String, new: String) {
        val common = old.commonPrefixWith(new).length
        browser?.deleteBackward(old.length - common)
        val insert = new.substring(common)
        if (insert.isNotEmpty()) browser?.insert(insert)
    }

    fun submitTyping() {
        when (keyboardTarget) {
            KeyboardTarget.address -> { AddressInput.url(draft)?.let { browser?.load(it) }; endTyping() }
            KeyboardTarget.page -> { browser?.submit(); endTyping() }
            KeyboardTarget.note -> endTyping()
            null -> {}
        }
    }
}
