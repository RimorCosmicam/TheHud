package com.thehud.apps

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/**
 * TheHud's accessibility service, for one thing only: an accessibility overlay is the one kind
 * of window that goes above DeX's taskbar, so with it on the glasses show the HUD and nothing
 * else. It reads nothing and touches nothing. (The class keeps its old name and place: Android
 * remembers an enabled service by them.)
 */
class HudAccessibility : AccessibilityService() {
    override fun onServiceConnected() { instance = this; com.thehud.glasses.GlassesPresenter.serviceChanged() }
    override fun onDestroy() { gone(); super.onDestroy() }
    override fun onUnbind(intent: Intent?): Boolean { gone(); return super.onUnbind(intent) }
    private fun gone() {
        if (instance !== this) return
        instance = null
        com.thehud.glasses.GlassesPresenter.serviceChanged()
    }
    override fun onInterrupt() {}
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    companion object {
        var instance: HudAccessibility? = null
            private set
    }
}

/** Whether the overlay's service is on, and the system's page to turn it on. */
object GlassesOverlayService {
    fun enabled(context: Context): Boolean {
        val mine = ComponentName(context, HudAccessibility::class.java).flattenToString()
        return Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            ?.split(':')?.any { it.equals(mine, ignoreCase = true) } == true
    }

    fun openSettings(context: Context) {
        runCatching {
            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
