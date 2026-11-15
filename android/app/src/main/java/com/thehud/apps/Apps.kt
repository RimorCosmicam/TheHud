package com.thehud.apps

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.ActivityOptions
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.provider.Settings
import android.view.Display
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import kotlin.math.abs
import kotlin.math.min

/**
 * Android's own apps on the glasses: the launcher's apps, started on the glasses' display at the
 * Apps panel's place, and worked from the phone through an accessibility service.
 */
class AppsProvider(private val context: Context) {
    private val icons = mutableMapOf<String, ImageBitmap>()

    fun list(): List<HudSnapshot.AppEntry> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .filter { it.activityInfo.packageName != context.packageName }
            .map { HudSnapshot.AppEntry(it.activityInfo.packageName, it.loadLabel(pm).toString()) }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
    }

    fun icon(packageName: String): ImageBitmap? = icons.getOrPut(packageName) {
        runCatching { context.packageManager.getApplicationIcon(packageName).toBitmap(96, 96).asImageBitmap() }.getOrNull()
            ?: return null
    }

    /** The glasses' canvas on its display: where a canvas point lands in the display's pixels. */
    class Mapping(val scale: Float, val left: Float, val top: Float) {
        fun pixels(p: Offset) = Offset(left + p.x * scale, top + p.y * scale)
        fun rect(r: androidx.compose.ui.geometry.Rect): Rect {
            val a = pixels(r.topLeft); val b = pixels(r.bottomRight)
            return Rect(a.x.toInt(), a.y.toInt(), b.x.toInt(), b.y.toInt())
        }
    }

    fun mapping(display: Display): Mapping {
        val bounds = runCatching {
            context.createDisplayContext(display).getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds
        }.getOrNull() ?: Rect(0, 0, 1920, 1080)
        val w = bounds.width().toFloat(); val h = bounds.height().toFloat()
        val scale = min(w / HudTheme.CANVAS_WIDTH, h / HudTheme.CANVAS_HEIGHT)
        return Mapping(scale, (w - HudTheme.CANVAS_WIDTH * scale) / 2, (h - HudTheme.CANVAS_HEIGHT * scale) / 2)
    }

    /** Starts the app on the glasses, in the panel's rectangle (in display pixels). */
    fun launch(packageName: String, display: Display, bounds: Rect): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        val options = ActivityOptions.makeBasic().setLaunchDisplayId(display.displayId).setLaunchBounds(bounds).toBundle()
        // A window of its own at the panel's place: DeX otherwise files apps into its desk, at a size
        // of its choosing and out of sight. The windowing mode is read from the bundle by its key.
        options.putInt("android.activity.windowingMode", 5)
        return runCatching { context.startActivity(intent, options); true }.getOrDefault(false)
    }

    val serviceEnabled: Boolean
        get() {
            val mine = ComponentName(context, HudAccessibility::class.java).flattenToString()
            return Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                ?.split(':')?.any { it.equals(mine, ignoreCase = true) } == true
        }

    fun openAccessibilitySettings() {
        runCatching {
            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}

/** The hands on the glasses' apps: taps, swipes and text, on one display only. */
class HudAccessibility : AccessibilityService() {
    // With the service on, the glasses go on an overlay above DeX's taskbar: tell the presenter.
    override fun onServiceConnected() { instance = this; com.thehud.glasses.GlassesPresenter.serviceChanged() }
    override fun onDestroy() { gone(); super.onDestroy() }
    override fun onUnbind(intent: Intent?): Boolean { gone(); return super.onUnbind(intent) }
    private fun gone() {
        stopFitting()
        if (instance !== this) return
        instance = null
        com.thehud.glasses.GlassesPresenter.serviceChanged()
    }
    override fun onInterrupt() {}
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        when (event?.eventType) {
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> { onWindowsChanged?.invoke(); later(250) }
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> later(250)
        }
    }

    private fun gesture(display: Int, path: Path, duration: Long): Boolean {
        val stroke = GestureDescription.StrokeDescription(path, 0, duration)
        val g = GestureDescription.Builder().addStroke(stroke).setDisplayId(display).build()
        return dispatchGesture(g, null, null)
    }

    // --- Fitting: DeX opens every app at a window size of its own (and ignores the size asked
    // for), so the window is taken by its title bar and corner and dragged onto the panel, the
    // way the wearer would with a mouse. DeX remembers each app's size, so it sticks.

    private class Goal(val display: Int, val packageName: String, val target: Rect) {
        var tries = 0
        var resizeOutside = true
        var busy = false
    }
    private var goal: Goal? = null
    private val main = Handler(Looper.getMainLooper())
    private val check = Runnable { step() }

    private fun later(ms: Long) {
        if (goal == null) return
        main.removeCallbacks(check)
        main.postDelayed(check, ms)
    }

    /** Puts the app's window on the display exactly over [target] (display pixels). */
    fun fit(display: Int, packageName: String, target: Rect) {
        goal = Goal(display, packageName, Rect(target))
        later(500)
    }

    fun stopFitting() { goal = null; main.removeCallbacks(check) }

    private fun window(g: Goal): Rect? {
        val windows = runCatching { windowsOnAllDisplays.get(g.display) }.getOrNull() ?: return null
        val w = windows.firstOrNull {
            it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.root?.packageName?.toString() == g.packageName
        } ?: return null
        return Rect().also { w.getBoundsInScreen(it) }
    }

    private fun step() {
        val g = goal ?: return
        if (g.busy) return
        val now = window(g) ?: run { if (++g.tries < 12) later(400) else stopFitting(); return }
        val t = g.target
        val near = 6
        val placed = abs(now.left - t.left) <= near && abs(now.top - t.top) <= near
        val sized = abs(now.right - t.right) <= near && abs(now.bottom - t.bottom) <= near
        if (placed && sized) { Log.i(TAG, "fitted ${g.packageName} at $now"); stopFitting(); return }
        if (++g.tries > 8) { Log.w(TAG, "gave up fitting ${g.packageName}: $now, wanted $t"); stopFitting(); return }
        val from: Offset; val to: Offset
        if (!placed) {
            // The title bar: DeX's caption runs along the window's top.
            val grab = Offset(now.exactCenterX(), now.top + 14f)
            from = grab; to = Offset(grab.x + (t.left - now.left), grab.y + (t.top - now.top))
        } else {
            // The bottom-right corner, its touch handle just outside the frame (or, failing that, inside).
            val inset = if (g.resizeOutside) -6f else 6f
            from = Offset(now.right - inset, now.bottom - inset); to = Offset(t.right - inset, t.bottom - inset)
            if (now.width() == lastWidth && now.height() == lastHeight) g.resizeOutside = !g.resizeOutside
            lastWidth = now.width(); lastHeight = now.height()
        }
        Log.i(TAG, "fitting ${g.packageName}: $now -> $t, drag $from -> $to")
        g.busy = true
        val press = GestureDescription.StrokeDescription(Path().apply { moveTo(from.x, from.y) }, 0, 160, true)
        val drag = press.continueStroke(Path().apply { moveTo(from.x, from.y); lineTo(to.x, to.y) }, 0, 360, false)
        val first = GestureDescription.Builder().addStroke(press).setDisplayId(g.display).build()
        val callback = object : GestureResultCallback() {
            override fun onCompleted(d: GestureDescription?) { g.busy = false; later(350) }
            override fun onCancelled(d: GestureDescription?) { g.busy = false; later(350) }
        }
        val started = dispatchGesture(first, object : GestureResultCallback() {
            override fun onCompleted(d: GestureDescription?) {
                if (!dispatchGesture(GestureDescription.Builder().addStroke(drag).setDisplayId(g.display).build(), callback, null)) {
                    g.busy = false
                }
            }
            override fun onCancelled(d: GestureDescription?) { g.busy = false; later(350) }
        }, null)
        if (!started) g.busy = false
    }
    private var lastWidth = 0
    private var lastHeight = 0

    fun tap(display: Int, at: Offset, long: Boolean = false) =
        gesture(display, Path().apply { moveTo(at.x, at.y) }, if (long) 650 else 40)

    /** A finger's swipe: content follows it, so a scroll down swipes up. */
    fun swipe(display: Int, from: Offset, to: Offset, duration: Long = 180) =
        gesture(display, Path().apply { moveTo(from.x, from.y); lineTo(to.x, to.y) }, duration)

    /** The focused field on the display, or the first one that takes text. */
    fun focused(display: Int): AccessibilityNodeInfo? {
        val windows = runCatching { windowsOnAllDisplays.get(display) }.getOrNull() ?: return null
        for (w in windows) {
            val root = w.root ?: continue
            root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)?.takeIf { it.isEditable }?.let { return it }
        }
        return null
    }

    /** Package names of the apps with windows on the display, topmost first. */
    fun packages(display: Int): List<String> =
        runCatching { windowsOnAllDisplays.get(display) }.getOrNull()?.mapNotNull { it.root?.packageName?.toString() } ?: emptyList()

    fun text(display: Int): String? = focused(display)?.text?.toString()

    fun setText(display: Int, text: String): Boolean {
        val node = focused(display) ?: return false
        val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun enter(display: Int): Boolean {
        val node = focused(display) ?: return false
        return node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
    }

    fun back() = performGlobalAction(GLOBAL_ACTION_BACK)

    companion object {
        var instance: HudAccessibility? = null
            private set
        var onWindowsChanged: (() -> Unit)? = null
        private const val TAG = "HudApps"
    }
}
