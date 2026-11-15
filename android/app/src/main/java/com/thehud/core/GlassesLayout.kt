package com.thehud.core

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size

/** The browser chrome's measurements, shared by the drawing and the hit test. */
object BrowserMetrics {
    const val BAR_INSET = 16f
    const val BAR_HEIGHT = 66f
    const val BUTTON_WIDTH = 78f
    const val MAX_TABS = 8
    const val CLOSE_WIDTH = 52f
    val contentTopInset get() = BAR_INSET + BAR_HEIGHT + 10f

    /** Back and forward on the left, new tab and reload on the right, tabs between; the active one doubled. */
    fun tabSegments(barWidth: Float, count: Int, active: Int): List<Pair<Float, Float>> {
        val left = BUTTON_WIDTH * 2
        val middle = maxOf(barWidth - BUTTON_WIDTH * 4, 0f)
        if (count <= 1) return listOf(left to middle)
        val unit = middle / (count + 1)
        var x = left
        return (0 until count).map { i ->
            val w = unit * if (i == active) 2 else 1
            (x to w).also { x += w }
        }
    }
}

/** What a click on the canvas landed on. */
sealed interface GlassesHit {
    data object Back : GlassesHit
    data object Forward : GlassesHit
    data object Reload : GlassesHit
    data object Address : GlassesHit
    data object NewTab : GlassesHit
    data class SelectTab(val index: Int) : GlassesHit
    data class CloseTab(val index: Int) : GlassesHit
    /** A point in the page, in the web view's own canvas points. */
    data class Page(val point: Offset) : GlassesHit
    data class Widget(val kind: HudPanelKind, val point: Offset, val size: Size) : GlassesHit
    data object None : GlassesHit
}

/**
 * Where things are on the 1920x1080 canvas. Arithmetic rather than something read back from the
 * views: the glasses take no touches, so the phone has to work out what is under the cursor.
 */
class GlassesLayout(
    val arrangement: HudArrangement = HudArrangement.standard,
    val solo: HudPanelKind? = null,
    val clearView: Boolean = false,
    tabCount: Int = 1,
    val activeTab: Int = 0,
    fullscreen: Boolean = false,
) {
    val tabCount = maxOf(tabCount, 1)
    val fullscreen: Boolean = fullscreen && !clearView &&
        (solo?.let { it == HudPanelKind.browser } ?: arrangement.isShown(HudPanelKind.browser))

    companion object {
        const val SLOT_WIDTH = 400f
        const val GAP = 24f
        const val ROW_HEIGHT = 270f
        val canvas = Size(HudTheme.CANVAS_WIDTH, HudTheme.CANVAS_HEIGHT)
        val slotHeight get() = (HudTheme.CANVAS_HEIGHT - HudTheme.SAFE_INSET * 2 - GAP * 2) / 3
        val safeFrame: Rect
            get() = Rect(HudTheme.SAFE_INSET, HudTheme.SAFE_INSET,
                         HudTheme.CANVAS_WIDTH - HudTheme.SAFE_INSET, HudTheme.CANVAS_HEIGHT - HudTheme.SAFE_INSET)

        fun rowFrame(index: Int, edge: HudEdge): Rect {
            val safe = safeFrame
            val count = HudArrangement.ROW.toFloat()
            val width = (safe.width - GAP * (count - 1)) / count
            val y = if (edge == HudEdge.top) safe.top else safe.bottom - ROW_HEIGHT
            return Rect(Offset(safe.left + index * (width + GAP), y), Size(width, ROW_HEIGHT))
        }

        fun rowMain(edge: HudEdge): Rect {
            val safe = safeFrame
            val y = if (edge == HudEdge.top) safe.top + ROW_HEIGHT + GAP else safe.top
            return Rect(Offset(safe.left, y), Size(safe.width, safe.height - ROW_HEIGHT - GAP))
        }

        fun slotFrame(side: HudSide, index: Int): Rect {
            val safe = safeFrame
            val x = if (side == HudSide.left) safe.left else safe.right - SLOT_WIDTH
            return Rect(Offset(x, safe.top + index * (slotHeight + GAP)), Size(SLOT_WIDTH, slotHeight))
        }

        fun bigSpan(sides: Set<HudSide>): Rect {
            val safe = safeFrame
            val minX = if (HudSide.left in sides) safe.left else safe.left + SLOT_WIDTH + GAP
            val maxX = if (HudSide.right in sides) safe.right else safe.right - SLOT_WIDTH - GAP
            return Rect(minX, safe.top, maxX, safe.bottom)
        }
    }

    private val drawsArrangement get() = !clearView && solo == null && !fullscreen

    val widgetFrames: List<Pair<HudPanelKind, Rect>>
        get() {
            if (!drawsArrangement) return emptyList()
            arrangement.strip?.let { edge -> return arrangement.shownRow.map { (k, i) -> k to rowFrame(i, edge) } }
            return arrangement.shownWidgets.map { it.kind to slotFrame(it.side, it.index) }
        }

    val bigFrames: List<Pair<HudPanelKind, Rect>>
        get() {
            if (clearView) return emptyList()
            if (fullscreen) return listOf(HudPanelKind.browser to Rect(Offset.Zero, canvas))
            solo?.let { return if (it.isBig) listOf(it to safeFrame) else emptyList() }
            val bigs = arrangement.orderedBigs
            if (bigs.isEmpty()) return emptyList()
            arrangement.strip?.let { return listOf(bigs[0].kind to rowMain(it)) }
            val span = bigSpan(arrangement.takenSides)
            val width = (span.width - GAP * (bigs.size - 1)) / bigs.size
            return bigs.mapIndexed { i, b -> b.kind to Rect(Offset(span.left + i * (width + GAP), span.top), Size(width, span.height)) }
        }

    val soloWidgetFrame: Rect? get() = if (!clearView && !fullscreen && solo != null && !solo.isBig) safeFrame else null

    fun frameOf(kind: HudPanelKind): Rect? = when {
        kind.isBig -> bigFrames.firstOrNull { it.first == kind }?.second
        solo == kind -> soloWidgetFrame
        else -> widgetFrames.firstOrNull { it.first == kind }?.second
    }

    val browserFrame get() = frameOf(HudPanelKind.browser)

    val barFrame: Rect?
        get() {
            if (fullscreen) return null
            val f = browserFrame ?: return null
            val i = BrowserMetrics.BAR_INSET
            return Rect(Offset(f.left + i, f.top + i), Size(f.width - i * 2, BrowserMetrics.BAR_HEIGHT))
        }

    fun isOverBar(p: Offset?) = p != null && barFrame?.contains(p) == true

    fun tabAt(p: Offset?): Int? {
        val bar = barFrame ?: return null
        if (p == null || !bar.contains(p)) return null
        val x = p.x - bar.left
        return BrowserMetrics.tabSegments(bar.width, tabCount, activeTab).indexOfFirst { x >= it.first && x < it.first + it.second }
            .takeIf { it >= 0 }
    }

    fun hitTest(p: Offset): GlassesHit {
        if (clearView) return GlassesHit.None
        soloWidgetFrame?.let { f -> solo?.let { return GlassesHit.Widget(it, p - f.topLeft, f.size) } }
        for ((kind, f) in widgetFrames) if (f.contains(p)) return GlassesHit.Widget(kind, p - f.topLeft, f.size)
        val frame = browserFrame
        if (frame == null || !frame.contains(p)) return GlassesHit.None
        barFrame?.let { bar ->
            if (bar.contains(p)) {
                val x = p.x - bar.left
                val b = BrowserMetrics.BUTTON_WIDTH
                if (x < b) return GlassesHit.Back
                if (x < b * 2) return GlassesHit.Forward
                if (x >= bar.width - b) return GlassesHit.Reload
                if (x >= bar.width - b * 2) return GlassesHit.NewTab
                val segs = BrowserMetrics.tabSegments(bar.width, tabCount, activeTab)
                val i = segs.indexOfFirst { x >= it.first && x < it.first + it.second }
                if (i < 0) return GlassesHit.None
                if (tabCount > 1 && x < segs[i].first + BrowserMetrics.CLOSE_WIDTH) return GlassesHit.CloseTab(i)
                return if (i == activeTab) GlassesHit.Address else GlassesHit.SelectTab(i)
            }
        }
        return GlassesHit.Page(p - frame.topLeft)
    }
}
