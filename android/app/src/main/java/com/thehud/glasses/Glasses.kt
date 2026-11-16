package com.thehud.glasses

import android.app.ActivityOptions
import android.app.Presentation
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableDoubleState
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.thehud.HudController
import com.thehud.R
import com.thehud.core.HudTheme
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.min

/**
 * The glasses' picture, at canvas units: whatever the display's pixels, one dp here is one point
 * of the 1920x1080 canvas, and the canvas is fitted to the display.
 */
@Composable
fun GlassesRoot() {
    BoxWithConstraints(Modifier.fillMaxSize()
        .background(Color.Black), contentAlignment = Alignment.Center) {
        val scale = min(constraints.maxWidth / HudTheme.CANVAS_WIDTH, constraints.maxHeight / HudTheme.CANVAS_HEIGHT)
            .takeIf { it > 0f } ?: 1f
        val eased = easedHeading()
        CompositionLocalProvider(LocalDensity provides Density(scale, 1f)) {
            Box(Modifier.requiredSize(HudTheme.CANVAS_WIDTH.dp, HudTheme.CANVAS_HEIGHT.dp)) {
                GlassesScreen(HudController.snapshot, HudController.layout, GlassesContent(
                    page = { LivePage() },
                    youtube = HudController.youtube?.let { player -> { LiveVideo(player) } },
                    mac = { LiveMac() },
                    mapGround = HudController.mapGround,
                    artwork = HudController.artwork,
                    photos = HudController.photoImages,
                    standIn = false,
                    heading = { eased.doubleValue }))
            }
        }
    }
    val context = LocalContext.current
    DisposableEffect(context) {
        HudController.glassesAttached(context)
        onDispose { HudController.glassesDetached() }
    }
}

/**
 * The compass, eased every frame toward the phone's latest reading, the way iOS animates the
 * heading: the sensor's steps become one glide, and the way round is always the short one.
 * Only the map's and the sky's drawing read it, so a turn redraws them and recomposes nothing.
 */
@Composable
private fun easedHeading(): MutableDoubleState {
    val eased = remember { mutableDoubleStateOf(HudController.heading.doubleValue) }
    LaunchedEffect(Unit) {
        var last = 0L
        while (true) withFrameNanos { now ->
            val dt = if (last == 0L) 0.0 else (now - last) / 1e9
            last = now
            val target = HudController.heading.doubleValue
            val gap = ((target - eased.doubleValue) % 360 + 540) % 360 - 180
            if (abs(gap) > 0.01) {
                val step = gap * (1 - exp(-dt.coerceAtMost(0.1) * 12))
                eased.doubleValue = ((eased.doubleValue + step) % 360 + 360) % 360
            }
        }
    }
    return eased
}

/** The active tab's web view, moved into the panel. */
@Composable
private fun LivePage() {
    val tab = HudController.browser ?: return
    key(tab) {
        AndroidView(factory = { tab.detach(); tab.view }, modifier = Modifier.fillMaxSize(), onRelease = { tab.detach() })
    }
}

/** The YouTube player's web view: one view, made once, placed by the layer and never moved between views. */
@Composable
private fun LiveVideo(player: com.thehud.youtube.YouTubePlayer) {
    AndroidView(factory = { player.detach(); player.view }, modifier = Modifier.fillMaxSize(), onRelease = { player.detach() })
}

/** The Mac's picture, decoded straight onto this view's surface. */
@Composable
private fun LiveMac() {
    AndroidView(factory = { c -> android.view.TextureView(c).also { HudController.attachMac(it) } }, modifier = Modifier.fillMaxSize())
}

/**
 * Something that is always resumed: the glasses keep drawing when the cover screen sleeps or the
 * phone is opened, which the phone's own activity would not allow.
 */
private class AlwaysOn : LifecycleOwner, SavedStateRegistryOwner {
    private val registry = LifecycleRegistry(this)
    private val saved = SavedStateRegistryController.create(this)
    override val lifecycle: Lifecycle get() = registry
    override val savedStateRegistry: SavedStateRegistry get() = saved.savedStateRegistry
    init { saved.performRestore(null) }
    fun resume() { registry.currentState = Lifecycle.State.RESUMED }
    fun destroy() { registry.currentState = Lifecycle.State.DESTROYED }
}

/** The glasses as a Presentation: our own window on the external display, in place of its mirror. */
private class GlassesPresentation(context: Context, display: Display) : Presentation(context, display, R.style.Theme_TheHud) {
    private val owner = AlwaysOn()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
        window?.decorView?.let {
            it.setViewTreeLifecycleOwner(owner)
            it.setViewTreeSavedStateRegistryOwner(owner)
        }
        owner.resume()
        setContentView(ComposeView(context).apply { setContent { GlassesRoot() } })
        window?.let(::immersive)
    }

    override fun onStop() {
        super.onStop()
        owner.destroy()
    }
}

/**
 * Finds the glasses and keeps a window on them. The Flip's own screens are display 0 (inside) and
 * a cover display; anything plugged in comes after them, as MiniDex found.
 */
object GlassesPresenter {
    private const val TAG = "Glasses"
    private var presentation: Presentation? = null
    private var overlay: GlassesOverlay? = null
    private var shownOn: Int? = null
    private lateinit var app: Context
    private var phoneDisplays: () -> Set<Int> = { emptySet() }

    /** The glasses' pixel size, for the settings page. */
    val shownDisplay: Display? get() = shownOn?.let { app.getSystemService(DisplayManager::class.java).getDisplay(it) }

    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = refresh()
        override fun onDisplayRemoved(displayId: Int) = refresh()
        override fun onDisplayChanged(displayId: Int) {}
    }

    fun start(context: Context, phone: () -> Set<Int>) {
        phoneDisplays = phone
        if (::app.isInitialized) { refresh(); return }
        app = context.applicationContext
        app.getSystemService(DisplayManager::class.java).registerDisplayListener(listener, Handler(Looper.getMainLooper()))
        refresh()
    }

    fun glassesDisplay(): Display? {
        val manager = app.getSystemService(DisplayManager::class.java)
        val phone = phoneDisplays() + Display.DEFAULT_DISPLAY
        // The cover screen (1 on the Flip 7) is flagged for presentations too: only what comes
        // after the phone's own two screens is the glasses.
        // DeX reports its display to apps as off, so the state is no guide.
        val candidates = manager.displays.filter { it.displayId >= 2 && it.displayId !in phone }
        return candidates.firstOrNull { it.flags and Display.FLAG_PRESENTATION != 0 } ?: candidates.maxByOrNull { it.displayId }
    }

    /** Our window back over whatever app was started on the glasses. */
    fun raise() {
        if (presentation != null || overlay != null) return
        val id = shownOn ?: return
        runCatching {
            val options = ActivityOptions.makeBasic().setLaunchDisplayId(id)
            app.startActivity(Intent(app, GlassesActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT), options.toBundle())
        }
    }

    /** The accessibility service came or went: the glasses move between the overlay and the presentation. */
    fun serviceChanged() {
        if (!::app.isInitialized) return
        Handler(Looper.getMainLooper()).post { shownOn = null; refresh() }
    }

    fun refresh() {
        val display = glassesDisplay()
        val service = com.thehud.apps.HudAccessibility.instance
        val upToDate = if (service != null) overlay != null else presentation?.isShowing == true
        if (display?.displayId == shownOn && upToDate) return
        presentation?.dismiss()
        presentation = null
        overlay?.remove()
        overlay = null
        shownOn = null
        if (display == null) return
        Log.i(TAG, "Glasses on display ${display.displayId} (${display.name})")
        // With TheHud's accessibility service on, an accessibility overlay: the one kind of window
        // that sits above DeX's taskbar, so the glasses show only the HUD.
        if (service != null) {
            val shown = runCatching { GlassesOverlay(service, display) }
                .onFailure { Log.w(TAG, "No overlay on ${display.displayId}", it) }.getOrNull()
            if (shown != null) { overlay = shown; shownOn = display.displayId; return }
        }
        // From the application rather than an activity: a window of its own, which stays up
        // whatever the cover screen does.
        val shown = runCatching { GlassesPresentation(app, display).also { it.show() } }
            .onFailure { Log.w(TAG, "No presentation on ${display.displayId}", it) }.getOrNull()
        if (shown != null) {
            presentation = shown
            shownOn = display.displayId
            shown.setOnDismissListener { if (presentation === shown) { presentation = null; shownOn = null } }
        } else {
            // DeX and other desktops take activities, not presentations.
            runCatching {
                val options = ActivityOptions.makeBasic().setLaunchDisplayId(display.displayId)
                app.startActivity(Intent(app, GlassesActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK), options.toBundle())
                shownOn = display.displayId
            }.onFailure { Log.w(TAG, "No activity on ${display.displayId}", it) }
        }
    }
}

/** The glasses as an accessibility overlay: above everything on the display, DeX's taskbar included. */
private class GlassesOverlay(service: android.accessibilityservice.AccessibilityService, display: Display) {
    private val owner = AlwaysOn()
    private val context = service.createDisplayContext(display)
        .createWindowContext(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY, null)
    private val manager = context.getSystemService(WindowManager::class.java)
    private val view = ComposeView(context).apply {
        setViewTreeLifecycleOwner(owner)
        setViewTreeSavedStateRegistryOwner(owner)
        setContent { GlassesRoot() }
    }

    init {
        owner.resume()
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            android.graphics.PixelFormat.TRANSLUCENT).apply {
            fitInsetsTypes = 0
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            title = "TheHud glasses"
        }
        manager.addView(view, params)
    }

    fun remove() {
        runCatching { manager.removeView(view) }
        owner.destroy()
    }
}

/** Over everything on the display: DeX's taskbar and bars are asked to go while our window is up. */
internal fun immersive(window: android.view.Window) {
    window.setDecorFitsSystemWindows(false)
    window.attributes = window.attributes.apply {
        layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
    }
    window.insetsController?.let {
        it.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        it.hide(android.view.WindowInsets.Type.systemBars())
    }
}

/** The glasses as an activity, for displays that are desktops. */
class GlassesActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent { GlassesRoot() }
        immersive(window)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        immersive(window)
    }
}
