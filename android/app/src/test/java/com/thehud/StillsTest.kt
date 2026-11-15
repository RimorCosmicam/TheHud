package com.thehud

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.captureRoboImage
import com.thehud.core.GlassesLayout
import com.thehud.core.HudArrangement
import com.thehud.core.HudEdge
import com.thehud.core.HudPanelKind
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTimer
import com.thehud.glasses.GlassesScreen
import androidx.compose.ui.geometry.Offset
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The glasses drawn to PNG at their own size, as hudshot does for the iPhone app. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w1920dp-h1080dp-land-mdpi")
class StillsTest {
    @get:Rule val compose = createComposeRule()

    private val snapshot = HudSnapshot(
        note = HudSnapshot.Note("Pick up the film\nCall back about Thursday"),
        browser = HudSnapshot.Browser(url = "developer.android.com", title = "Android Developers",
            tabs = listOf("Android Developers", "Open-Meteo"), canGoBack = true),
        cursor = Offset(1180f, 120f),
    )

    private fun shot(name: String, snapshot: HudSnapshot, layout: GlassesLayout) {
        compose.setContent { GlassesScreen(snapshot, layout) }
        compose.onRoot().captureRoboImage("../../out/android/$name.png")
    }

    @Test fun desk() = shot("glasses-desk", snapshot, GlassesLayout(HudArrangement.standard, tabCount = 2))

    @Test fun street() = shot("glasses-street", snapshot.copy(cursor = null),
        GlassesLayout(HudArrangement.standard.setStrip(HudEdge.top)))

    @Test fun clock() {
        val timer = HudTimer().set(25).toggle(0).reading(312_000)
        shot("glasses-clock", snapshot.copy(timer = timer, cursor = null), GlassesLayout(solo = HudPanelKind.clock))
    }

    @Test fun weather() = shot("glasses-weather", snapshot.copy(cursor = null), GlassesLayout(solo = HudPanelKind.weather))
}
