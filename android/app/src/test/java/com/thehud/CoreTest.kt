package com.thehud

import androidx.compose.ui.geometry.Offset
import com.thehud.core.BrowserMetrics
import com.thehud.core.GlassesHit
import com.thehud.core.GlassesLayout
import com.thehud.core.HudArrangement
import com.thehud.core.HudEdge
import com.thehud.core.HudPanelKind
import com.thehud.core.HudSide
import com.thehud.core.HudSnapshot
import com.thehud.core.HudSpot
import com.thehud.core.HudTimer
import com.thehud.core.WeatherIcon
import com.thehud.data.OpenMeteo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The rules the phone and the glasses share, checked without either. */
class CoreTest {
    private val standard = HudArrangement.standard

    @Test fun hidingKeepsThePlace() {
        val hidden = standard.toggleHidden(HudPanelKind.weather)
        assertFalse(hidden.isShown(HudPanelKind.weather))
        assertEquals(HudSpot.Slot(HudSide.left, 1), hidden.spot(HudPanelKind.weather))
        assertTrue(hidden.toggleHidden(HudPanelKind.weather).isShown(HudPanelKind.weather))
    }

    @Test fun anyAppTakesTheCentre() {
        val a = standard.setCentre(HudPanelKind.calendar)
        assertEquals(HudPanelKind.calendar, a.centre?.kind)
        assertTrue(a.isShown(HudPanelKind.calendar))
        // And back with the picker.
        assertEquals(HudPanelKind.browser, a.setCentre(HudPanelKind.browser).centre?.kind)
        // A widget moved into the centre swaps with what was there; the wheel and clicks find it.
        val clock = standard.setCentre(HudPanelKind.clock)
        assertEquals(HudPanelKind.clock, clock.centre?.kind)
        assertFalse(HudPanelKind.clock in clock.left)
        val hit = GlassesLayout(clock).let { it.hitTest(it.centre!!.second.center) }
        assertTrue(hit is GlassesHit.Centre && hit.kind == HudPanelKind.clock)
    }

    @Test fun placingOnATakenSlotSwaps() {
        val moved = standard.place(HudPanelKind.clock, HudSpot.Slot(HudSide.left, 2))
        assertEquals(HudPanelKind.clock, moved.left[2])
        assertEquals(HudPanelKind.map, moved.left[0])
    }

    @Test fun theBrowserTakesTheRestOfTheCanvas() {
        val layout = GlassesLayout(standard)
        val browser = layout.browserFrame!!
        val clock = layout.frameOf(HudPanelKind.clock)!!
        assertEquals(clock.right + GlassesLayout.GAP, browser.left, 0.01f)
        // Not reaching over a side, it leaves the right-hand column free.
        assertEquals(HudTheme_SAFE_RIGHT - GlassesLayout.SLOT_WIDTH - GlassesLayout.GAP, browser.right, 0.01f)
        val over = GlassesLayout(standard.place(HudPanelKind.browser, HudSpot.Slot(HudSide.right, 0))).browserFrame!!
        assertEquals(HudTheme_SAFE_RIGHT, over.right, 0.01f)
    }

    @Test fun theRowLayoutPutsWidgetsOnTop() {
        val row = standard.setStrip(HudEdge.top)
        val layout = GlassesLayout(row)
        val frames = layout.widgetFrames
        // The standard's three widgets, along the top.
        assertEquals(3, frames.size)
        assertTrue(frames.all { it.second.top == 64f })
        assertTrue(layout.browserFrame!!.top > frames[0].second.bottom)
    }

    @Test fun theArrangedBrowserIsThePageAlone() {
        val layout = GlassesLayout(standard)
        assertNull(layout.barFrame)
        val f = layout.browserFrame!!
        assertEquals(GlassesHit.Page(Offset(10f, 10f)), layout.hitTest(f.topLeft + Offset(10f, 10f)))
        assertTrue(GlassesLayout(standard, editingAddress = true).barFrame != null)
    }

    @Test fun clicksFindTheBarAndThePage() {
        val layout = GlassesLayout(standard, solo = HudPanelKind.browser)
        val bar = layout.barFrame!!
        assertEquals(GlassesHit.Back, layout.hitTest(Offset(bar.left + 10, bar.center.y)))
        assertEquals(GlassesHit.Reload, layout.hitTest(Offset(bar.right - 10, bar.center.y)))
        assertEquals(GlassesHit.Address, layout.hitTest(bar.center))
        val page = layout.hitTest(layout.browserFrame!!.center)
        assertTrue(page is GlassesHit.Page)
    }

    @Test fun tabsSplitTheBar() {
        val segments = BrowserMetrics.tabSegments(1000f, 3, 1)
        assertEquals(segments[1].second, segments[0].second * 2, 0.01f)
        val layout = GlassesLayout(standard, solo = HudPanelKind.browser, tabCount = 3, activeTab = 0)
        val bar = layout.barFrame!!
        val second = BrowserMetrics.tabSegments(bar.width, 3, 0)[1]
        val x = bar.left + second.first + second.second - 5
        assertEquals(GlassesHit.SelectTab(1), layout.hitTest(Offset(x, bar.center.y)))
    }

    @Test fun clearViewShowsNothing() {
        val layout = GlassesLayout(standard, clearView = true)
        assertTrue(layout.widgetFrames.isEmpty() && layout.bigFrames.isEmpty())
        assertEquals(GlassesHit.None, layout.hitTest(Offset(960f, 540f)))
    }

    @Test fun aSoloWidgetFillsTheSafeArea() {
        val layout = GlassesLayout(standard, solo = HudPanelKind.clock)
        assertEquals(GlassesLayout.safeFrame, layout.soloWidgetFrame)
        assertNull(layout.browserFrame)
    }

    @Test fun theTimerCountsDownAndPauses() {
        var t = HudTimer().set(1)
        t = t.toggle(0)
        assertEquals("0:30", t.reading(30_000).text)
        t = t.toggle(30_000)
        assertEquals(HudSnapshot.TimerState.paused, t.reading(90_000).state)
        assertEquals("0:30", t.reading(90_000).text)
        t = t.toggle(90_000)
        assertEquals(HudSnapshot.TimerState.done, t.reading(120_000).state)
    }

    @Test fun weatherDecodes() {
        val body = """{"current":{"time":"2026-11-15T14:45","temperature_2m":24.6,"weather_code":61,"is_day":1},
            "hourly":{"time":["2026-11-15T14:00","2026-11-15T15:00","2026-11-15T16:00"],"temperature_2m":[24.0,23.2,21.9],
            "weather_code":[61,3,0],"is_day":[1,1,0]},
            "daily":{"temperature_2m_max":[26.1],"temperature_2m_min":[17.4]}}"""
        val w = OpenMeteo.decode(body, "Lisbon")
        assertEquals(25, w.temperature)
        assertEquals("LIGHT RAIN", w.condition)
        assertEquals(WeatherIcon.rain, w.icon)
        assertEquals("LISBON", w.place)
        assertEquals(listOf("NOW", "15", "16"), w.hours.map { it.label })
        assertEquals(WeatherIcon.moon, w.hours[2].icon)
    }

    @Test
    fun themeAccentsMatchTheIPhone() {
        val expected = listOf(0xFFD8A628, 0xFF9ABE50, 0xFF00CBA9, 0xFF36BCFC, 0xFFA6A2FF, 0xFFE18BDA, 0xFFF985A2, 0xFFFA8C66)
        assertEquals(expected, com.thehud.core.ThemeColor.entries.map { com.thehud.core.OKLCH.rotate(0xFFD8A628, it.shift) })
    }

    private companion object {
        const val HudTheme_SAFE_RIGHT = 1920f - 64f
    }
}
