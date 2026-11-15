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
import android.provider.Settings
import android.view.Display
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
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
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        val options = ActivityOptions.makeBasic().setLaunchDisplayId(display.displayId).setLaunchBounds(bounds)
        return runCatching { context.startActivity(intent, options.toBundle()); true }.getOrDefault(false)
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
    override fun onServiceConnected() { instance = this }
    override fun onDestroy() { if (instance === this) instance = null; super.onDestroy() }
    override fun onUnbind(intent: Intent?): Boolean { if (instance === this) instance = null; return super.onUnbind(intent) }
    override fun onInterrupt() {}
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED) onWindowsChanged?.invoke()
    }

    private fun gesture(display: Int, path: Path, duration: Long): Boolean {
        val stroke = GestureDescription.StrokeDescription(path, 0, duration)
        val g = GestureDescription.Builder().addStroke(stroke).setDisplayId(display).build()
        return dispatchGesture(g, null, null)
    }

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
    }
}
