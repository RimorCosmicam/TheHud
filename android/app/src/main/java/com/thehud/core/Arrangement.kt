package com.thehud.core

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import kotlinx.serialization.Serializable

// A port of the iPhone app's Arrangement.swift: the same rules, so a scene behaves the same on
// either phone.

/**
 * Every app. Each has three sizes, as on the iPhone: a widget in a slot, the one app in the
 * centre (the Apps Center), or fullscreen when held.
 */
@Serializable
enum class HudPanelKind {
    browser, mac,
    clock, weather, map, activity, sky, music, note, captions, youtube,
    calendar, photos, prompter, camera, books;

    /** The browser and the Mac: panels of their own with live content, worked by the cursor. In a slot they are a live preview. */
    val isBig: Boolean get() = this == browser || this == mac

    val title: String get() = name.uppercase()

    companion object {
        /** Every app, in the order the iPhone's picker lists them. */
        val apps = listOf(browser, mac, youtube, map, music, calendar, photos, camera, books, prompter, note, sky, weather, clock, activity, captions)
        val available: Set<HudPanelKind> = entries.toSet()
    }
}

@Serializable enum class HudSide { left, right }

/** The edge a row of widgets runs along, in the row layout. */
@Serializable enum class HudEdge { top, bottom }

/** Where something can be dropped in the phone's editor. */
sealed interface HudSpot {
    data class Slot(val side: HudSide, val index: Int) : HudSpot
    data class Row(val index: Int) : HudSpot
    data object Middle : HudSpot
    data object Off : HudSpot
}

@Serializable
data class Big(val kind: HudPanelKind, val side: HudSide? = null)

/**
 * What is on the glasses and where: a port of the iPhone app's Arrangement.swift, the same rules
 * so the two phones agree. Columns: three widget slots down each side and the centre between,
 * which can reach over one side. Row: four widgets along the top or bottom and the centre in
 * the rest. The centre holds any one app. Each layout keeps its own slots; the centre is shared.
 *
 * `bigs` is the centre as a list of at most one, as the iPhone stores it.
 * Immutable: every change returns a new arrangement, which is what Compose wants to watch.
 */
@Serializable
data class HudArrangement(
    val left: List<HudPanelKind?> = List(SLOTS) { null },
    val right: List<HudPanelKind?> = List(SLOTS) { null },
    val bigs: List<Big> = emptyList(),
    val hidden: Set<HudPanelKind> = emptySet(),
    val row: List<HudPanelKind?> = List(ROW) { null },
    val strip: HudEdge? = null,
) {
    val isRow: Boolean get() = strip != null

    /** The Apps Center: the one app in the middle, whether switched off for now or not. */
    val centre: Big? get() = bigs.firstOrNull()

    fun slots(side: HudSide) = if (side == HudSide.left) left else right

    fun spot(kind: HudPanelKind): HudSpot {
        if (centre?.kind == kind) return HudSpot.Middle
        if (isRow) {
            val i = row.indexOf(kind)
            return if (i >= 0) HudSpot.Row(i) else HudSpot.Off
        }
        for (side in HudSide.entries) {
            val i = slots(side).indexOf(kind)
            if (i >= 0) return HudSpot.Slot(side, i)
        }
        return HudSpot.Off
    }

    fun isPlaced(kind: HudPanelKind) = spot(kind) != HudSpot.Off
    fun isShown(kind: HudPanelKind) = isPlaced(kind) && kind !in hidden

    fun sideOf(kind: HudPanelKind): HudSide? = if (isRow) null else centre?.takeIf { it.kind == kind }?.side

    /** The centre as it is on the glasses: nothing when switched off, never over a side in the row. */
    val orderedBigs: List<Big>
        get() {
            val c = centre ?: return emptyList()
            if (c.kind in hidden) return emptyList()
            return listOf(if (isRow) Big(c.kind) else c)
        }

    val takenSides: Set<HudSide> get() = orderedBigs.mapNotNull { it.side }.toSet()

    data class Placed(val kind: HudPanelKind, val side: HudSide, val index: Int)

    /** Widgets drawn: placed, not switched off, and not under the centre's side. */
    val shownWidgets: List<Placed>
        get() {
            if (isRow) return emptyList()
            val taken = takenSides
            return HudSide.entries.filter { it !in taken }.flatMap { side ->
                slots(side).mapIndexedNotNull { i, kind ->
                    kind?.takeIf { it !in hidden }?.let { Placed(it, side, i) }
                }
            }
        }

    val shownRow: List<Pair<HudPanelKind, Int>>
        get() = if (!isRow) emptyList() else
            row.mapIndexedNotNull { i, kind -> kind?.takeIf { it !in hidden }?.let { it to i } }

    /** The centre as placed, switched off or not: what the phone's miniature draws. */
    val placedBigsInOrder: List<Big>
        get() = centre?.let { listOf(if (isRow) Big(it.kind) else it) } ?: emptyList()

    val unplaced: List<HudPanelKind> get() = HudPanelKind.apps.filter { !isPlaced(it) }

    // ------------------------------------------------------------------ changes

    /** Switches layout. The first time into the row it takes the first four widgets showing. */
    fun setStrip(edge: HudEdge?): HudArrangement {
        var next = this
        if (edge != null && !isRow && row.all { it == null }) {
            val widgets = (left + right).filterNotNull().filter { it !in hidden }
            next = next.copy(row = padded(widgets.take(ROW), ROW))
        }
        return next.copy(strip = edge)
    }

    /** A tap: off the glasses for now, keeping its place; or back on. */
    fun toggleHidden(kind: HudPanelKind): HudArrangement {
        if (!isPlaced(kind)) return this
        return copy(hidden = if (kind in hidden) hidden - kind else hidden + kind)
    }

    private fun withSlot(side: HudSide, index: Int, kind: HudPanelKind?): HudArrangement =
        if (side == HudSide.left) copy(left = left.toMutableList().also { it[index] = kind })
        else copy(right = right.toMutableList().also { it[index] = kind })

    /** Takes a kind off the glasses. */
    fun remove(kind: HudPanelKind): HudArrangement {
        var next = this
        if (centre?.kind == kind) next = next.copy(bigs = emptyList())
        next = if (isRow) next.copy(row = row.map { if (it == kind) null else it })
        else next.copy(left = left.map { if (it == kind) null else it }, right = right.map { if (it == kind) null else it })
        return if (!next.isPlaced(kind)) next.copy(hidden = next.hidden - kind) else next
    }

    /**
     * Puts an app in the centre, as the phone's app picker does. Where it came from takes the
     * app that was there, so two apps swap; from nowhere, the old one goes back with the icons.
     * The centre keeps the side it reaches over.
     */
    fun setCentre(kind: HudPanelKind): HudArrangement = makeCentre(kind, centre?.side)

    private fun makeCentre(kind: HudPanelKind, side: HudSide?): HudArrangement {
        val old = centre
        if (old?.kind == kind) return copy(bigs = listOf(Big(kind, side)), hidden = hidden - kind)
        val swapIn = old?.kind
        var next = when (val from = spot(kind)) {
            is HudSpot.Slot -> withSlot(from.side, from.index, swapIn)
            is HudSpot.Row -> copy(row = row.toMutableList().also { it[from.index] = swapIn })
            else -> this
        }
        // The other layout's slots keep their places, but not a copy of the centre.
        next = next.copy(
            left = next.left.map { if (it == kind) null else it },
            right = next.right.map { if (it == kind) null else it },
            row = next.row.map { if (it == kind) null else it },
            bigs = listOf(Big(kind, side)),
        )
        var hid = next.hidden - kind
        if (swapIn != null) hid = hid - swapIn
        return next.copy(hidden = hid)
    }

    /**
     * Drops a kind somewhere, as the editor does. On the middle it becomes the centre app. On a
     * slot it is a widget there and whatever was there swaps into its old place (or goes back to
     * the icons); the centre itself dropped on a side reaches over that side instead.
     */
    fun place(kind: HudPanelKind, at: HudSpot): HudArrangement {
        if (at == HudSpot.Off) return remove(kind)
        if (at == HudSpot.Middle) return makeCentre(kind, null)
        if (isRow) return placeInRow(kind, at)
        val slot = at as? HudSpot.Slot ?: return this
        if (slot.index !in 0 until SLOTS) return this
        if (centre?.kind == kind) return copy(bigs = listOf(Big(kind, slot.side)), hidden = hidden - kind)
        val from = spot(kind)
        val occupant = slots(slot.side)[slot.index]
        if (occupant == kind) return copy(hidden = hidden - kind)
        var next = this
        var hid = hidden
        if (from is HudSpot.Slot) next = next.withSlot(from.side, from.index, occupant)
        else if (occupant != null) hid = hid - occupant
        next = next.withSlot(slot.side, slot.index, kind)
        return next.copy(hidden = hid - kind)
    }

    /** The row: widgets swap places along it. The centre dropped on the row swaps with the widget there. */
    private fun placeInRow(kind: HudPanelKind, at: HudSpot): HudArrangement {
        val r = at as? HudSpot.Row ?: return this
        if (r.index !in row.indices) return this
        val occupant = row[r.index]
        if (centre?.kind == kind) return occupant?.let { makeCentre(it, null) } ?: this
        if (occupant == kind) return copy(hidden = hidden - kind)
        val next = row.toMutableList()
        var hid = hidden
        val from = row.indexOf(kind)
        if (from >= 0) next[from] = occupant else if (occupant != null) hid = hid - occupant
        next[r.index] = kind
        return copy(row = next, hidden = hid - kind)
    }

    companion object {
        const val SLOTS = 3
        const val ROW = 4

        fun padded(list: List<HudPanelKind?>, count: Int = SLOTS): List<HudPanelKind?> =
            (list + List(count) { null }).take(count)

        fun of(
            left: List<HudPanelKind?> = emptyList(), right: List<HudPanelKind?> = emptyList(),
            centre: Big? = null, row: List<HudPanelKind?> = emptyList(), strip: HudEdge? = null,
        ) = HudArrangement(padded(left), padded(right), listOfNotNull(centre), emptySet(), padded(row, ROW), strip)

        /** The browser in the centre; the clock, the weather and the map down the left. */
        val standard = of(left = listOf(HudPanelKind.clock, HudPanelKind.weather, HudPanelKind.map),
                          centre = Big(HudPanelKind.browser))
    }
}

/** One of three ready arrangements. Each keeps its own edits; holding its name puts the preset back. */
@Serializable
data class HudScene(val name: String, val arrangement: HudArrangement) {
    companion object {
        /** Bumped when a preset changes enough that saved scenes should take it. */
        const val VERSION = 3

        // The iPhone's presets.
        val presets = listOf(
            // At a desk: the browser in the centre, the Mac live in a slot to swap in.
            HudScene("DESK", HudArrangement.of(
                left = listOf(HudPanelKind.clock, HudPanelKind.calendar, HudPanelKind.weather),
                right = listOf(HudPanelKind.mac, HudPanelKind.music, HudPanelKind.note),
                centre = Big(HudPanelKind.browser))),
            // Walking: one row of widgets along the top and the map under it.
            HudScene("STREET", HudArrangement.of(
                left = listOf(HudPanelKind.calendar, HudPanelKind.weather, HudPanelKind.clock),
                right = listOf(HudPanelKind.music, HudPanelKind.activity, HudPanelKind.captions),
                centre = Big(HudPanelKind.map),
                row = listOf(HudPanelKind.clock, HudPanelKind.weather, HudPanelKind.calendar, HudPanelKind.music),
                strip = HudEdge.top)),
            // Evening: something to watch, and the sky.
            HudScene("NIGHT", HudArrangement.of(
                left = listOf(HudPanelKind.clock, HudPanelKind.weather, HudPanelKind.sky),
                right = listOf(HudPanelKind.music, HudPanelKind.photos, HudPanelKind.browser),
                centre = Big(HudPanelKind.youtube))),
        )
    }
}

/** The phone's miniature of the glasses: the same layout squeezed into the phone's rectangle. */
class MiniLayout(val size: Size, val strip: HudEdge? = null) {
    val rowHeight get() = size.height * GlassesLayout.ROW_HEIGHT / GlassesLayout.safeFrame.height
    val sideWidth get() = size.width * GlassesLayout.SLOT_WIDTH / GlassesLayout.safeFrame.width
    val gap get() = maxOf(4f, size.width * GlassesLayout.GAP / GlassesLayout.safeFrame.width)
    val slotHeight get() = (size.height - gap * 2) / 3

    fun rowSlot(index: Int): Rect {
        val count = HudArrangement.ROW.toFloat()
        val width = (size.width - gap * (count - 1)) / count
        val y = if (strip == HudEdge.bottom) size.height - rowHeight else 0f
        return Rect(Offset(index * (width + gap), y), Size(width, rowHeight))
    }

    fun slot(side: HudSide, index: Int) = Rect(
        Offset(if (side == HudSide.left) 0f else size.width - sideWidth, index * (slotHeight + gap)),
        Size(sideWidth, slotHeight))

    val middle: Rect
        get() = if (strip != null)
            Rect(Offset(0f, if (strip == HudEdge.top) rowHeight + gap else 0f), Size(size.width, size.height - rowHeight - gap))
        else Rect(Offset(sideWidth + gap, 0f), Size(size.width - (sideWidth + gap) * 2, size.height))

    fun bigFrames(arrangement: HudArrangement): List<Pair<HudPanelKind, Rect>> {
        val bigs = arrangement.placedBigsInOrder
        if (bigs.isEmpty()) return emptyList()
        if (strip != null) return listOf(bigs[0].kind to middle)
        val sides = bigs.mapNotNull { it.side }.toSet()
        val minX = if (HudSide.left in sides) 0f else sideWidth + gap
        val maxX = if (HudSide.right in sides) size.width else size.width - sideWidth - gap
        val width = (maxX - minX - gap * (bigs.size - 1)) / bigs.size
        return bigs.mapIndexed { i, big -> big.kind to Rect(Offset(minX + i * (width + gap), 0f), Size(width, size.height)) }
    }

    fun spot(at: Offset): HudSpot {
        if (strip != null) {
            val band = rowSlot(0)
            if (at.y < band.top - gap / 2 || at.y > band.bottom + gap / 2) return HudSpot.Middle
            val w = band.width + gap
            return HudSpot.Row((at.x / w).toInt().coerceIn(0, HudArrangement.ROW - 1))
        }
        val row = (at.y / (slotHeight + gap)).toInt().coerceIn(0, HudArrangement.SLOTS - 1)
        if (at.x < sideWidth + gap / 2) return HudSpot.Slot(HudSide.left, row)
        if (at.x > size.width - sideWidth - gap / 2) return HudSpot.Slot(HudSide.right, row)
        return HudSpot.Middle
    }
}
