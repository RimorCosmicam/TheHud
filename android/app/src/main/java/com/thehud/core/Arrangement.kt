package com.thehud.core

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import kotlinx.serialization.Serializable

// A port of the iPhone app's Arrangement.swift: the same rules, so a scene behaves the same on
// either phone.

/** Everything the glasses can show: two big things for the middle, and the widgets beside it. */
@Serializable
enum class HudPanelKind {
    browser, mac, apps,
    clock, weather, map, activity, sky, music, note, captions, youtube;

    /** The browser, the Mac and Android apps: the middle, reaching over a side, worked by the cursor. */
    val isBig: Boolean get() = this == browser || this == mac || this == apps

    val title: String get() = name.uppercase()

    companion object {
        val bigs = listOf(browser, mac, apps)
        val widgets = listOf(clock, weather, map, activity, sky, music, note, captions, youtube)
        /** Everything: the iPhone's panels, and Android's own apps. */
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
 * What is on the glasses and where, in one of two layouts. Columns: three widget slots down each
 * side, big panels in the middle, each able to reach over a side. Row: four widgets along the top
 * or bottom and one big panel in the rest. Each layout keeps its own places.
 *
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

    fun slots(side: HudSide) = if (side == HudSide.left) left else right

    private val rowBig: Big? get() = bigs.firstOrNull()

    fun spot(kind: HudPanelKind): HudSpot {
        if (isRow) {
            val i = row.indexOf(kind)
            if (i >= 0) return HudSpot.Row(i)
            return if (rowBig?.kind == kind) HudSpot.Middle else HudSpot.Off
        }
        for (side in HudSide.entries) {
            val i = slots(side).indexOf(kind)
            if (i >= 0) return HudSpot.Slot(side, i)
        }
        return if (bigs.any { it.kind == kind }) HudSpot.Middle else HudSpot.Off
    }

    fun isPlaced(kind: HudPanelKind) = spot(kind) != HudSpot.Off
    fun isShown(kind: HudPanelKind) = isPlaced(kind) && kind !in hidden

    fun sideOf(kind: HudPanelKind): HudSide? = if (isRow) null else bigs.firstOrNull { it.kind == kind }?.side

    /** The big panels on the glasses, left to right. */
    val orderedBigs: List<Big>
        get() {
            if (isRow) return rowBig?.takeIf { it.kind !in hidden }?.let { listOf(Big(it.kind)) } ?: emptyList()
            val shown = bigs.filter { it.kind !in hidden }
            return shown.filter { it.side == HudSide.left } + shown.filter { it.side == null } +
                shown.filter { it.side == HudSide.right }
        }

    val takenSides: Set<HudSide> get() = orderedBigs.mapNotNull { it.side }.toSet()

    data class Placed(val kind: HudPanelKind, val side: HudSide, val index: Int)

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

    val placedBigsInOrder: List<Big>
        get() = if (isRow) listOfNotNull(bigs.firstOrNull()?.let { Big(it.kind) })
        else bigs.filter { it.side == HudSide.left } + bigs.filter { it.side == null } +
            bigs.filter { it.side == HudSide.right }

    val unplaced: List<HudPanelKind> get() = HudPanelKind.entries.filter { !isPlaced(it) }

    // ------------------------------------------------------------------ changes

    fun setStrip(edge: HudEdge?): HudArrangement {
        var next = this
        if (edge != null && !isRow && row.all { it == null }) {
            val widgets = (left + right).filterNotNull().filter { it !in hidden }
            next = next.copy(row = padded(widgets.take(ROW), ROW))
        }
        return next.copy(strip = edge)
    }

    fun toggleHidden(kind: HudPanelKind): HudArrangement {
        if (!isPlaced(kind)) return this
        return copy(hidden = if (kind in hidden) hidden - kind else hidden + kind)
    }

    fun remove(kind: HudPanelKind): HudArrangement {
        if (isRow) {
            var bigs = bigs
            if (rowBig?.kind == kind) bigs = bigs.drop(1)
            val next = copy(row = row.map { if (it == kind) null else it }, bigs = bigs)
            return if (!next.isPlaced(kind)) next.copy(hidden = hidden - kind) else next
        }
        return copy(
            left = left.map { if (it == kind) null else it },
            right = right.map { if (it == kind) null else it },
            bigs = bigs.filter { it.kind != kind },
            hidden = hidden - kind,
        )
    }

    /**
     * Drops a kind somewhere, as the editor does. A widget on a slot takes it and whatever was
     * there swaps into its old slot (or goes back to the icons). A big panel in the middle sits
     * there; on a side it reaches over that side.
     */
    fun place(kind: HudPanelKind, at: HudSpot): HudArrangement {
        if (at == HudSpot.Off) return remove(kind)
        if (isRow) return placeInRow(kind, at)
        if (kind.isBig) {
            val side = (at as? HudSpot.Slot)?.side
            var list = bigs.map { if (side != null && it.side == side && it.kind != kind) it.copy(side = null) else it }
            list = if (list.any { it.kind == kind }) list.map { if (it.kind == kind) it.copy(side = side) else it }
            else list + Big(kind, side)
            return copy(bigs = list, hidden = hidden - kind)
        }
        val slot = at as? HudSpot.Slot ?: return this
        if (slot.index !in 0 until SLOTS) return this
        val from = spot(kind)
        val occupant = slots(slot.side)[slot.index]
        if (occupant == kind) return copy(hidden = hidden - kind)
        val l = left.toMutableList()
        val r = right.toMutableList()
        fun set(side: HudSide, i: Int, k: HudPanelKind?) { if (side == HudSide.left) l[i] = k else r[i] = k }
        var hid = hidden
        if (from is HudSpot.Slot) set(from.side, from.index, occupant) else if (occupant != null) hid = hid - occupant
        set(slot.side, slot.index, kind)
        return copy(left = l, right = r, hidden = hid - kind)
    }

    private fun placeInRow(kind: HudPanelKind, at: HudSpot): HudArrangement {
        if (kind.isBig) {
            val existing = bigs.firstOrNull { it.kind == kind } ?: Big(kind)
            return copy(bigs = listOf(existing) + bigs.filter { it.kind != kind }, hidden = hidden - kind)
        }
        val r = at as? HudSpot.Row ?: return this
        if (r.index !in row.indices) return this
        val occupant = row[r.index]
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
            bigs: List<Big> = emptyList(), row: List<HudPanelKind?> = emptyList(), strip: HudEdge? = null,
        ) = HudArrangement(padded(left), padded(right), bigs, emptySet(), padded(row, ROW), strip)

        val standard = of(left = listOf(HudPanelKind.clock, HudPanelKind.weather, HudPanelKind.note),
                          right = listOf(HudPanelKind.music, HudPanelKind.activity, HudPanelKind.captions),
                          bigs = listOf(Big(HudPanelKind.browser)))
    }
}

/** One of three ready arrangements. Each keeps its own edits; holding its name puts the preset back. */
@Serializable
data class HudScene(val name: String, val arrangement: HudArrangement) {
    companion object {
        /** Bumped when a preset changes enough that saved scenes should take it. */
        const val VERSION = 2

        val presets = listOf(
            // At a desk: the browser in the middle, the Mac over the right.
            HudScene("DESK", HudArrangement.of(
                left = listOf(HudPanelKind.clock, HudPanelKind.weather, HudPanelKind.note),
                right = listOf(HudPanelKind.music, HudPanelKind.activity, HudPanelKind.captions),
                bigs = listOf(Big(HudPanelKind.browser), Big(HudPanelKind.mac, HudSide.right)))),
            // Walking: one row of widgets along the top and a single app under it.
            HudScene("STREET", HudArrangement.of(
                left = listOf(HudPanelKind.map, HudPanelKind.weather, HudPanelKind.clock),
                right = listOf(HudPanelKind.music, HudPanelKind.activity, HudPanelKind.captions),
                bigs = listOf(Big(HudPanelKind.browser)),
                row = listOf(HudPanelKind.clock, HudPanelKind.weather, HudPanelKind.map, HudPanelKind.music),
                strip = HudEdge.top)),
            // Evening: something to read, and the sky.
            HudScene("NIGHT", HudArrangement.of(
                left = listOf(HudPanelKind.clock, HudPanelKind.weather, HudPanelKind.sky),
                right = listOf(HudPanelKind.music, HudPanelKind.note, HudPanelKind.activity),
                bigs = listOf(Big(HudPanelKind.browser)))),
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
