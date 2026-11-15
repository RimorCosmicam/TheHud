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
    /** A point on the Mac's picture, 0 to 1 across it. */
    data class Mac(val point: Offset) : GlassesHit
    /** The Android apps panel: its bar's buttons, or a point in its content, in panel points. */
    data class Apps(val target: AppsLayout.Target, val point: Offset) : GlassesHit
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
    desktopAspect: Float = 16f / 10f,
    /** Typing an address from the phone: the bar shows wherever the browser is, to show what is typed. */
    val editingAddress: Boolean = false,
) {
    val desktopAspect = if (desktopAspect > 0) desktopAspect else 16f / 10f
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
    val desktopFrame get() = frameOf(HudPanelKind.mac)
    val appsFrame get() = frameOf(HudPanelKind.apps)

    /** The Mac's picture inside its panel, fitted without cropping. */
    val desktopPicture: Rect?
        get() {
            val f = desktopFrame ?: return null
            val w = minOf(f.width, f.height * desktopAspect)
            val h = w / desktopAspect
            return Rect(Offset(f.center.x - w / 2, f.center.y - h / 2), Size(w, h))
        }

    /**
     * The address bar and tabs: only when the browser is held open on its own (or an address is being
     * typed). In the arrangement the panel is the page alone, edge to edge.
     */
    val barFrame: Rect?
        get() {
            if (fullscreen || (solo != HudPanelKind.browser && !editingAddress)) return null
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
        desktopPicture?.let { pic ->
            if (pic.contains(p)) return GlassesHit.Mac(Offset((p.x - pic.left) / pic.width, (p.y - pic.top) / pic.height))
        }
        appsFrame?.let { f ->
            if (f.contains(p)) return GlassesHit.Apps(AppsLayout.target(p - f.topLeft, f.size), p - f.topLeft)
        }
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

/** The Android apps panel: a bar like the browser's, and the app (or the grid of apps) under it. */
object AppsLayout {
    enum class Target { home, back, close, content }

    val contentTop get() = BrowserMetrics.contentTopInset
    const val TILE_WIDTH = 200f
    const val TILE_HEIGHT = 190f
    const val GRID_INSET = 40f

    fun bar(size: Size) = Rect(Offset(BrowserMetrics.BAR_INSET, BrowserMetrics.BAR_INSET),
        Size(size.width - BrowserMetrics.BAR_INSET * 2, BrowserMetrics.BAR_HEIGHT))

    /** Where the app's own window goes, in panel points. */
    fun content(size: Size) = Rect(0f, contentTop, size.width, size.height)

    fun target(p: Offset, size: Size): Target {
        val bar = bar(size)
        if (!bar.contains(p)) return Target.content
        val x = p.x - bar.left
        val b = BrowserMetrics.BUTTON_WIDTH
        return when {
            x < b -> Target.home
            x < b * 2 -> Target.back
            x >= bar.width - b -> Target.close
            else -> Target.content
        }
    }

    fun columns(size: Size) = maxOf(1, ((size.width - GRID_INSET * 2) / TILE_WIDTH).toInt())
    fun rows(size: Size) = maxOf(1, ((size.height - contentTop - GRID_INSET) / TILE_HEIGHT).toInt())

    fun tile(slot: Int, size: Size): Rect {
        val cols = columns(size)
        val used = cols * TILE_WIDTH
        val x0 = (size.width - used) / 2
        return Rect(Offset(x0 + slot % cols * TILE_WIDTH, contentTop + GRID_INSET / 2 + slot / cols * TILE_HEIGHT),
            Size(TILE_WIDTH, TILE_HEIGHT))
    }

    /** The app under a point of the grid, as an index into the list. */
    fun app(at: Offset, size: Size, scrollRow: Int, count: Int): Int? {
        val cols = columns(size)
        for (slot in 0 until cols * rows(size)) {
            if (tile(slot, size).contains(at)) {
                val i = scrollRow * cols + slot
                return i.takeIf { it < count }
            }
        }
        return null
    }

    fun maxRow(count: Int, size: Size): Int {
        val cols = columns(size)
        return maxOf(0, (count + cols - 1) / cols - rows(size))
    }
}

/** The Maps app's floating controls, for drawing and for hit testing. */
class MapsLayout(val resultCount: Int = 0, val navigating: Boolean = false) {
    enum class Target { none, search, endRoute, transport, zoomIn, zoomOut, result }
    data class Hit(val target: Target, val index: Int = 0)

    companion object {
        const val MARGIN = 28f
        const val CARD_WIDTH = 640f
        const val SEARCH_HEIGHT = 72f
        const val ROW_HEIGHT = 88f
        const val BUTTON_SIZE = 76f
        const val TRIP_HEIGHT = 104f
        const val TRIP_BUTTON_WIDTH = 132f
    }

    val panel get() = GlassesLayout.safeFrame
    val searchFrame get() = Rect(Offset(panel.left + MARGIN, panel.top + MARGIN), Size(CARD_WIDTH, SEARCH_HEIGHT))
    fun resultFrame(i: Int) = Rect(Offset(searchFrame.left, searchFrame.bottom + 12 + i * ROW_HEIGHT), Size(CARD_WIDTH, ROW_HEIGHT))
    val turnFrame get() = Rect(searchFrame.topLeft, Size(CARD_WIDTH, 200f))
    val tripFrame get() = Rect(Offset(panel.left + MARGIN, panel.bottom - MARGIN - TRIP_HEIGHT), Size(CARD_WIDTH + 260, TRIP_HEIGHT))
    val endFrame get() = Rect(Offset(tripFrame.right - 12 - TRIP_BUTTON_WIDTH, tripFrame.top + 14), Size(TRIP_BUTTON_WIDTH, tripFrame.height - 28))
    val transportFrame get() = endFrame.translate(-(TRIP_BUTTON_WIDTH + 10), 0f)
    val zoomInFrame get() = Rect(Offset(panel.right - MARGIN - BUTTON_SIZE, panel.center.y - BUTTON_SIZE - 6), Size(BUTTON_SIZE, BUTTON_SIZE))
    val zoomOutFrame get() = zoomInFrame.translate(0f, BUTTON_SIZE + 12)

    fun hitTest(p: Offset): Hit {
        if (zoomInFrame.contains(p)) return Hit(Target.zoomIn)
        if (zoomOutFrame.contains(p)) return Hit(Target.zoomOut)
        if (navigating) {
            if (endFrame.contains(p)) return Hit(Target.endRoute)
            if (transportFrame.contains(p)) return Hit(Target.transport)
            return Hit(Target.none)
        }
        if (searchFrame.contains(p)) return Hit(Target.search)
        for (i in 0 until resultCount) if (resultFrame(i).contains(p)) return Hit(Target.result, i)
        return Hit(Target.none)
    }
}

/** The clock app's timer card, in the app's own points: scroll to set, click to start, right-click to reset. */
object ClockAppLayout {
    val timerCard = Rect(Offset(824f, 330f), Size(440f, 320f))
}

/** Where Now Playing's buttons are, for drawing and for clicks. */
object MusicLayout {
    enum class Control { previous, playPause, next }

    fun buttons(size: Size, large: Boolean): List<Pair<Control, Rect>> {
        val width = if (large) 150f else 76f
        val height = if (large) 110f else 56f
        val spacing = if (large) 28f else 12f
        val total = width * 3 + spacing * 2
        val x0 = if (large) 700f else (size.width - total) / 2
        val y = if (large) 640f else size.height - 26 - height
        return Control.entries.mapIndexed { i, c -> c to Rect(Offset(x0 + i * (width + spacing), y), Size(width, height)) }
    }

    fun control(at: Offset, size: Size, large: Boolean) = buttons(size, large).firstOrNull { it.second.contains(at) }?.first
}

/** Where everything sits in the YouTube app held up alone, in the safe frame's points (1792 by 952). */
object YouTubeAppLayout {
    sealed interface Target {
        data class Tab(val tab: HudSnapshot.YouTube.Tab) : Target
        data object NowPlaying : Target
        data class Card(val index: Int) : Target
        data object Video : Target
    }

    val size = Size(1792f, 952f)
    const val COLUMNS = 4
    const val VISIBLE_ROWS = 2
    private const val GRID_X = 72f
    private const val GRID_Y = 150f
    const val CARD_WIDTH = 388f
    private const val CARD_GAP = 32f
    const val THUMB_HEIGHT = 218f
    private const val CARD_HEIGHT = 330f
    private const val ROW_GAP = 34f
    val nowPlayingTile = Rect(Offset(1240f, 34f), Size(480f, 84f))
    val tileVideo = Rect(Offset(1242f, 36f), Size(142f, 80f))

    private fun tabWidth(tab: HudSnapshot.YouTube.Tab) = when (tab) {
        HudSnapshot.YouTube.Tab.home -> 150f
        HudSnapshot.YouTube.Tab.subscriptions -> 290f
        HudSnapshot.YouTube.Tab.search -> 180f
    }

    fun tabFrame(index: Int, tabs: List<HudSnapshot.YouTube.Tab>): Rect {
        var x = 72f
        tabs.forEachIndexed { i, tab ->
            val w = tabWidth(tab)
            if (i == index) return Rect(Offset(x, 44f), Size(w, 60f))
            x += w + 14
        }
        return Rect.Zero
    }

    fun cardFrame(slot: Int): Rect {
        val column = slot % COLUMNS
        val row = slot / COLUMNS
        return Rect(Offset(GRID_X + column * (CARD_WIDTH + CARD_GAP), GRID_Y + row * (CARD_HEIGHT + ROW_GAP)),
            Size(CARD_WIDTH, CARD_HEIGHT))
    }

    fun target(p: Offset, youtube: HudSnapshot.YouTube): Target? {
        if (youtube.page == HudSnapshot.YouTube.Page.player) return Target.Video
        youtube.tabs.forEachIndexed { i, tab -> if (tabFrame(i, youtube.tabs).contains(p)) return Target.Tab(tab) }
        if (youtube.hasVideo && nowPlayingTile.contains(p)) return Target.NowPlaying
        val list = youtube.list(youtube.tab)
        for (slot in 0 until COLUMNS * VISIBLE_ROWS) {
            if (cardFrame(slot).contains(p)) {
                val index = youtube.scrollRow * COLUMNS + slot
                return if (index < list.size) Target.Card(index) else null
            }
        }
        return null
    }

    fun maxRow(count: Int) = maxOf(0, (count + COLUMNS - 1) / COLUMNS - VISIBLE_ROWS)
}
