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
import com.thehud.core.HudScene
import com.thehud.core.SkyCatalogue
import com.thehud.core.SkyModel
import com.thehud.core.SkyView
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

    @Test fun night() = shot("glasses-night", snapshot.copy(cursor = null, sky = skyAt()), GlassesLayout(HudScene.presets[2].arrangement))

    @Test fun music() = shot("glasses-music", snapshot.copy(cursor = null), GlassesLayout(solo = HudPanelKind.music))
    @Test fun activity() = shot("glasses-activity", snapshot.copy(cursor = null), GlassesLayout(solo = HudPanelKind.activity))
    @Test fun captions() = shot("glasses-captions", snapshot.copy(cursor = null), GlassesLayout(solo = HudPanelKind.captions))
    @Test fun note() = shot("glasses-note", snapshot.copy(cursor = null), GlassesLayout(solo = HudPanelKind.note))
    @Test fun youtube() = shot("glasses-youtube", snapshot.copy(cursor = Offset(700f, 330f)), GlassesLayout(solo = HudPanelKind.youtube))

    @Test fun maps() = shot("glasses-maps", snapshot.copy(cursor = null, maps = HudSnapshot.Maps(
        navigation = HudSnapshot.Maps.Navigation("Miradouro da Graça", "Turn left onto Rua da Graça", HudSnapshot.Maneuver.left,
            "120 M", "9 MIN", "750 M", "10:02"))), GlassesLayout(solo = HudPanelKind.map))

    @Test fun mapsSearch() = shot("glasses-maps-search", snapshot.copy(cursor = null, maps = HudSnapshot.Maps(query = "café", isEditing = true,
        results = listOf(HudSnapshot.Maps.Place("Café A Brasileira", "Rua Garrett 120, Lisboa", "1.2 KM"),
            HudSnapshot.Maps.Place("Café Nicola", "Praça Dom Pedro IV 24", "1.5 KM")))), GlassesLayout(solo = HudPanelKind.map))

    @Test fun sky() = shot("glasses-sky", snapshot.copy(cursor = null, sky = skyAt(full = true),
        skyView = SkyView(selected = "moon")), GlassesLayout(solo = HudPanelKind.sky))

    @Test fun desk2() = shot("glasses-mac", snapshot.copy(cursor = null), GlassesLayout(HudScene.presets[0].arrangement))

    @Test fun apps() = shot("glasses-apps", snapshot.copy(cursor = Offset(500f, 300f), apps = HudSnapshot.Apps(
        list = listOf("Calculator", "Calendar", "Camera", "Chrome", "Clock", "Contacts", "Files", "Gallery", "Gmail", "Maps", "Messages",
            "Photos", "Play Store", "Settings", "Spotify").map { HudSnapshot.AppEntry("com.example.${it.lowercase()}", it) })),
        GlassesLayout(solo = HudPanelKind.apps))

    private fun skyAt(full: Boolean = false): HudSnapshot.Sky {
        val catalogue = if (full) SkyCatalogue(java.io.File("../../Sources/HudCore/Resources/Sky/sky.json").readText()) else null
        // Lisbon, a November evening.
        return SkyModel.compute(java.util.Date(1_794_772_800_000L), 38.71, -9.14, catalogue, java.util.TimeZone.getTimeZone("Europe/Lisbon"))
    }
}
