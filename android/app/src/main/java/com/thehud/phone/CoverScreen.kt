package com.thehud.phone

import android.annotation.SuppressLint
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Apps
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.DesktopMac
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.KeyboardHide
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Map
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.SmartDisplay
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material.icons.rounded.StickyNote2
import androidx.compose.material.icons.rounded.VerticalAlignTop
import androidx.compose.material.icons.rounded.ViewColumn
import androidx.compose.material.icons.rounded.WbCloudy
import androidx.compose.material.icons.rounded.VerticalAlignBottom
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.thehud.HudController
import com.thehud.padTitle
import com.thehud.data.CaptionsLog
import com.thehud.data.CaptionsEngine
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import com.thehud.KeyboardTarget
import com.thehud.NoteAction
import com.thehud.PhoneAction
import com.thehud.PhonePad
import com.thehud.TimerAction
import com.thehud.core.BrowserMetrics
import com.thehud.core.HudArrangement
import com.thehud.core.HudEdge
import com.thehud.core.HudPanelKind
import com.thehud.core.HudSide
import com.thehud.core.HudSnapshot
import com.thehud.core.HudSpot
import com.thehud.core.HudTheme
import com.thehud.core.MiniLayout
import com.thehud.glasses.GlassesPresenter
import com.thehud.hasPhoneControls
import com.thehud.touchpad.GestureEvent
import com.thehud.touchpad.GestureRecognizer
import com.thehud.ui.HalftoneBackground
import kotlin.math.roundToInt

// The iPhone's phone screen, fitted to the Flip's cover screen (about 400 by 440 points, the
// cameras in its lower right corner): the icons, GLASSES with its scenes, the glasses as chips,
// the tabs, and the touchpad below. Hold GLASSES to arrange.

private val chipShape = RoundedCornerShape(50)
private val tileShape = RoundedCornerShape(8.dp)

private fun View.tick() = performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
private fun View.thud() = performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)

val HudPanelKind.icon: ImageVector
    get() = when (this) {
        HudPanelKind.browser -> Icons.Rounded.Language
        HudPanelKind.mac -> Icons.Rounded.DesktopMac
        HudPanelKind.apps -> Icons.Rounded.Apps
        HudPanelKind.clock -> Icons.Rounded.Schedule
        HudPanelKind.weather -> Icons.Rounded.WbCloudy
        HudPanelKind.map -> Icons.Rounded.Map
        HudPanelKind.activity -> Icons.Rounded.DirectionsWalk
        HudPanelKind.sky -> Icons.Rounded.NightsStay
        HudPanelKind.music -> Icons.Rounded.MusicNote
        HudPanelKind.note -> Icons.Rounded.StickyNote2
        HudPanelKind.captions -> Icons.Rounded.ClosedCaption
        HudPanelKind.youtube -> Icons.Rounded.SmartDisplay
    }

/** A drag in progress, in root pixels, and where the miniature is, in the same pixels. */
private class Editor {
    var drag by mutableStateOf<Pair<HudPanelKind, Offset>?>(null)
    var held by mutableStateOf<HudPanelKind?>(null)
    var mini by mutableStateOf(Rect.Zero)

    fun spot(at: Offset, strip: HudEdge?): HudSpot? {
        if (!mini.contains(at)) return null
        return MiniLayout(mini.size, strip).spot(at - mini.topLeft)
    }

    fun drop(kind: HudPanelKind, at: Offset, removing: Boolean) {
        val c = HudController
        val spot = spot(at, c.arrangement.strip)
        if (spot != null) {
            if (!kind.isBig && spot == HudSpot.Middle) return
            c.perform(PhoneAction.Place(kind, spot))
        } else if (removing && c.arrangement.isPlaced(kind)) {
            // Dragged off the glasses: back with the icons.
            c.perform(PhoneAction.Place(kind, HudSpot.Off))
        }
    }
}

@Composable
fun CoverScreen() {
    val c = HudController
    val editor = remember { Editor() }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
            ToolBar()
            if (c.showingSettings) {
                SettingsPage()
            } else {
                SettingsArea(editor)
                // Arranging, the editor has the touchpad's room.
                if (!c.editingGlasses) {
                    PadHeader()
                    // The pad runs to the bottom edge: the cameras simply sit over a corner of it.
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        when {
                            c.pad == PhonePad.app && c.solo?.hasPhoneControls == true -> AppControls(c.solo!!)
                            c.pad == PhonePad.remote -> RemotePad(Modifier.fillMaxSize())
                            else -> Touchpad(Modifier.fillMaxSize())
                        }
                    }
                }
            }
        }
        // The chip under the finger, lifted above everything while it is dragged.
        editor.drag?.let { (kind, at) ->
            val density = LocalDensity.current
            val w = with(density) { 92.dp.toPx() }
            val h = with(density) { 40.dp.toPx() }
            Box(Modifier.offset { IntOffset((at.x - w / 2).roundToInt(), (at.y - h / 2).roundToInt()) }
                .size(92.dp, 40.dp).scale(1.12f)) {
                MiniChip(kind, ChipState.lifted, big = false)
            }
        }
        KeyboardProxy()
    }
}

// ------------------------------------------------------------------ the icons

/**
 * The browser's chrome is on the glasses too, but steering a cursor onto a back arrow is slow; a
 * thumb on a button is not. So the commands you reach for constantly live here as well.
 */
@Composable
private fun ToolBar() {
    val c = HudController
    val b = c.snapshot.browser
    Row(Modifier.fillMaxWidth().height(46.dp).background(HudTheme.surface).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically) {
        ToolButton(Icons.Rounded.ChevronLeft, enabled = b.canGoBack) { c.perform(PhoneAction.Back) }
        ToolButton(Icons.Rounded.ChevronRight, enabled = b.canGoForward) { c.perform(PhoneAction.Forward) }
        ToolButton(Icons.Rounded.Refresh) { c.perform(PhoneAction.Reload) }
        ToolButton(Icons.Rounded.Home) { c.perform(PhoneAction.Home) }
        ToolButton(if (b.isFavorite) Icons.Rounded.Star else Icons.Rounded.StarBorder,
            enabled = !b.isHome, lit = b.isFavorite) { c.perform(PhoneAction.Favorite) }
        ToolButton(Icons.Rounded.Search, lit = c.keyboardTarget == KeyboardTarget.address) { c.perform(PhoneAction.Address) }
        ToolButton(if (c.keyboardTarget != null) Icons.Rounded.KeyboardHide else Icons.Rounded.Keyboard,
            lit = c.keyboardTarget != null) { c.perform(PhoneAction.Keyboard) }
        Box(Modifier.padding(horizontal = 4.dp).size(1.dp, 20.dp).background(Color.White.copy(alpha = 0.12f)))
        ToolButton(Icons.Rounded.Settings, lit = c.showingSettings) { c.showingSettings = !c.showingSettings }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.ToolButton(
    icon: ImageVector, enabled: Boolean = true, lit: Boolean = false, action: () -> Unit,
) {
    val view = LocalView.current
    Box(Modifier.weight(1f).fillMaxHeight().clickable(enabled = enabled) { view.tick(); action() },
        contentAlignment = Alignment.Center) {
        // State by brightness alone, as the Mont material asks.
        Image(icon, null, Modifier.size(24.dp),
            colorFilter = ColorFilter.tint(when { lit -> HudTheme.accent; enabled -> HudTheme.ink; else -> HudTheme.inkFaint }))
    }
}


// ------------------------------------------------------------------ GLASSES

@Composable
private fun SettingsArea(editor: Editor) {
    val c = HudController
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Header()
        Miniature(editor, Modifier.fillMaxWidth().height(if (c.editingGlasses) 168.dp else 84.dp))
        if (c.editingGlasses) Tray(editor) else TabStrip()
    }
}

/** GLASSES: a tap clears the view, a hold arranges. The scenes sit beside it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Header() {
    val c = HudController
    val view = LocalView.current
    val editing = c.editingGlasses
    Row(verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.combinedClickable(
            onLongClick = { if (!editing) { view.thud(); c.perform(PhoneAction.EditGlasses(true)) } },
        ) { view.tick(); c.perform(if (editing) PhoneAction.EditGlasses(false) else PhoneAction.ClearView) }
            .padding(vertical = 6.dp).padding(end = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            BasicText(when { editing -> "ARRANGING"; c.clearView -> "CLEAR VIEW"; c.solo != null -> "FULLSCREEN"; else -> "GLASSES" },
                style = HudTheme.mont(14f, tracking = 2.6f, color = if (editing || c.clearView) HudTheme.accent else HudTheme.inkDim),
                maxLines = 1)
            if (!editing) Box(Modifier.size(6.dp).background(if (c.glassesConnected) HudTheme.accent else HudTheme.inkFaint, chipShape))
        }
        Spacer(Modifier.weight(1f))
        if (editing) {
            Box(Modifier.height(30.dp).clip(chipShape).background(HudTheme.accent)
                .clickable { view.tick(); c.perform(PhoneAction.EditGlasses(false)) }.padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center) {
                BasicText("DONE", style = HudTheme.mont(12f, tracking = 2f, color = Color.Black))
            }
        } else {
            // The scenes: a tap switches, a hold puts that one back as it was preset.
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                c.scenes.forEachIndexed { i, scene ->
                    val chosen = i == c.sceneIndex
                    Box(Modifier.height(26.dp).clip(chipShape)
                        .background(if (chosen) HudTheme.accent else Color.White.copy(alpha = 0.07f))
                        .combinedClickable(onLongClick = { view.thud(); c.perform(PhoneAction.ResetScene(i)) }) {
                            view.tick(); c.perform(PhoneAction.Scene(i))
                        }.padding(horizontal = 9.dp), contentAlignment = Alignment.Center) {
                        BasicText(scene.name, style = HudTheme.mont(9.5f, tracking = 1.1f, color = if (chosen) Color.Black else HudTheme.inkDim))
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ the miniature

enum class ChipState { on, off, covered, solo, ghost, lifted, tray }

private fun chipState(kind: HudPanelKind, editor: Editor): ChipState {
    val c = HudController
    val a = c.arrangement
    if (editor.drag?.first == kind) return ChipState.ghost
    if (c.solo == kind) return ChipState.solo
    if (c.solo != null || kind in a.hidden) return ChipState.off
    val side = (a.spot(kind) as? HudSpot.Slot)?.side
    if (!kind.isBig && side != null && !a.isRow && side in a.takenSides) return ChipState.covered
    return ChipState.on
}

/** The glasses as chips, in their places: tap one to switch it off or on, hold it to have it alone. */
@Composable
private fun Miniature(editor: Editor, modifier: Modifier) {
    val c = HudController
    val a = c.arrangement
    val editing = c.editingGlasses
    BoxWithConstraints(modifier.onGloballyPositioned { editor.mini = it.boundsInRoot() }
        .alpha(if (c.clearView && !editing) 0.35f else 1f)) {
        val mini = MiniLayout(Size(maxWidth.value, maxHeight.value), a.strip)
        val drag = editor.drag
        val target = drag?.let { editor.spot(it.second, a.strip) }
        val draggingWidget = drag != null && !drag.first.isBig

        fun Modifier.at(r: Rect) = this.offset(r.left.dp, r.top.dp).size(r.width.dp, r.height.dp)

        if (a.isRow) {
            for (i in 0 until HudArrangement.ROW) {
                Slot(a.row[i], editor, target == HudSpot.Row(i) && draggingWidget, Modifier.at(mini.rowSlot(i)))
            }
        } else {
            for (side in HudSide.entries) for (i in 0 until HudArrangement.SLOTS) {
                Slot(a.slots(side)[i], editor, target == HudSpot.Slot(side, i) && draggingWidget, Modifier.at(mini.slot(side, i)))
            }
        }
        val bigs = mini.bigFrames(a)
        if (bigs.isEmpty()) {
            Box(Modifier.at(mini.middle).border(1.dp, Color.White.copy(alpha = if (editing) 0.18f else 0.07f), RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center) {
                BasicText(if (editing) "DRAG THE BROWSER HERE" else "OPEN", style = HudTheme.mont(8f, tracking = 1.5f, color = HudTheme.inkFaint))
            }
        }
        for ((kind, frame) in bigs) Chip(kind, editor, big = true, Modifier.at(frame))
        if (drag != null && drag.first.isBig && target != null) {
            var frame = mini.middle
            if (target is HudSpot.Slot && mini.strip == null) {
                frame = if (target.side == HudSide.left) Rect(0f, 0f, mini.middle.right, mini.size.height)
                else Rect(mini.middle.left, 0f, mini.size.width, mini.size.height)
            }
            Box(Modifier.at(frame).border(2.dp, HudTheme.accent, RoundedCornerShape(10.dp)))
        }
    }
}

@Composable
private fun Slot(kind: HudPanelKind?, editor: Editor, highlighted: Boolean, modifier: Modifier) {
    if (kind != null) {
        Box(modifier) {
            Chip(kind, editor, big = false, Modifier.fillMaxSize())
            if (highlighted) Box(Modifier.fillMaxSize().border(2.dp, HudTheme.accent, tileShape))
        }
    } else {
        Box(modifier.border(if (highlighted) 2.dp else 1.dp,
            if (highlighted) HudTheme.accent else Color.White.copy(alpha = if (HudController.editingGlasses) 0.2f else 0.06f), tileShape))
    }
}

@Composable
private fun Chip(kind: HudPanelKind, editor: Editor, big: Boolean, modifier: Modifier) {
    val editing = HudController.editingGlasses
    Box(modifier.panelGestures(kind, editor, editing, inTray = false).scale(if (editor.held == kind) 1.08f else 1f)) {
        MiniChip(kind, chipState(kind, editor), big, wiggle = editing)
    }
}

/**
 * Outside arranging: a tap switches it off or on; held and let go, it goes fullscreen; held or
 * pulled and dragged, it moves. Arranging, or in the tray, it just drags.
 */
private fun Modifier.panelGestures(kind: HudPanelKind, editor: Editor, editing: Boolean, inTray: Boolean): Modifier = this.composed {
    val view = LocalView.current
    var origin by remember { mutableStateOf(Offset.Zero) }
    this.onGloballyPositioned { origin = it.positionInRoot() }.pointerInput(kind, editing, inTray) {
        val slop = (if (editing || inTray) 2.dp else 10.dp).toPx()
        awaitEachGesture {
            val down = awaitFirstDown()
            down.consume()
            var at = down.position
            // Until the hold time: a lift is a tap, a move is a drag.
            val early = withTimeoutOrNull(400L) {
                while (true) {
                    val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: return@withTimeoutOrNull "up"
                    if (!change.pressed) return@withTimeoutOrNull "up"
                    at = change.position
                    change.consume()
                    if ((at - down.position).getDistance() > slop) return@withTimeoutOrNull "move"
                }
                @Suppress("UNREACHABLE_CODE") "up"
            }
            if (early == "up") {
                if (!editing && !inTray) { view.tick(); HudController.perform(PhoneAction.TapPanel(kind)) }
                return@awaitEachGesture
            }
            var dragging = early == "move"
            if (!dragging && !editing && !inTray) { editor.held = kind; view.thud() }
            while (true) {
                val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                at = change.position
                change.consume()
                if (!change.pressed) break
                if (dragging || (at - down.position).getDistance() > slop) {
                    dragging = true
                    editor.held = null
                    editor.drag = kind to (origin + at)
                }
            }
            editor.held = null
            if (dragging) {
                editor.drag = null
                editor.drop(kind, origin + at, removing = editing || inTray)
            } else if (!editing && !inTray) {
                view.tick()
                HudController.perform(PhoneAction.Solo(kind))
            }
        }
    }
}

/** One panel in the miniature or the tray: its icon and name. */
@Composable
fun MiniChip(kind: HudPanelKind, state: ChipState, big: Boolean, wiggle: Boolean = false) {
    val fg = when (state) {
        ChipState.solo -> HudTheme.accent
        ChipState.on, ChipState.lifted, ChipState.tray -> HudTheme.ink
        else -> HudTheme.inkFaint
    }
    val bg = when (state) {
        ChipState.solo -> HudTheme.accent.copy(alpha = 0.14f)
        ChipState.on, ChipState.lifted -> Color(0xFF212121)
        ChipState.tray -> Color(0xFF1A1A1A)
        else -> Color(0xFF0F0F0F)
    }
    val tilt = if (wiggle) {
        rememberInfiniteTransition(label = "wiggle").animateFloat(-1.2f, 1.2f,
            infiniteRepeatable(tween(140, easing = LinearEasing), RepeatMode.Reverse), label = "tilt").value
    } else 0f
    Box(Modifier.fillMaxSize().rotate(tilt).alpha(if (state == ChipState.ghost) 0.25f else 1f)
        .clip(tileShape).background(bg)
        .border(1.dp, if (state == ChipState.solo) HudTheme.accent else Color.White.copy(alpha = if (state == ChipState.on) 0.12f else 0.05f), tileShape),
        contentAlignment = Alignment.Center) {
        if (state == ChipState.on || state == ChipState.solo) {
            Box(Modifier.align(Alignment.TopCenter).padding(horizontal = 6.dp).fillMaxWidth().height(2.dp).background(HudTheme.accent))
        }
        val icon = @Composable { Image(kind.icon, null, Modifier.size(if (big) 18.dp else 12.dp), colorFilter = ColorFilter.tint(fg)) }
        val text = @Composable {
            BasicText(kind.title, style = HudTheme.mont(if (big) 8.5f else 7.5f, tracking = 1f, color = fg), maxLines = 1,
                overflow = TextOverflow.Clip)
        }
        if (big) Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) { icon(); text() }
        else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(horizontal = 3.dp)) { icon(); text() }
    }
}

// ------------------------------------------------------------------ arranging

/** Everything not on the glasses, to drag on, and the choice of layout. */
@Composable
private fun Tray(editor: Editor) {
    val c = HudController
    val a = c.arrangement
    val view = LocalView.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Columns down both sides, or one row of widgets along the top or the bottom.
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (edge in listOf(null, HudEdge.top, HudEdge.bottom)) {
                val chosen = a.strip == edge
                Row(Modifier.weight(1f).height(30.dp).clip(chipShape)
                    .background(if (chosen) HudTheme.accent else Color.White.copy(alpha = 0.07f))
                    .clickable { view.tick(); c.perform(PhoneAction.Layout(edge)) },
                    horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Image(when (edge) { null -> Icons.Rounded.ViewColumn; HudEdge.top -> Icons.Rounded.VerticalAlignTop; else -> Icons.Rounded.VerticalAlignBottom },
                        null, Modifier.size(14.dp), colorFilter = ColorFilter.tint(if (chosen) Color.Black else HudTheme.inkDim))
                    Spacer(Modifier.width(5.dp))
                    BasicText(when (edge) { null -> "COLUMNS"; HudEdge.top -> "TOP ROW"; else -> "BOTTOM ROW" },
                        style = HudTheme.mont(8.5f, tracking = 1f, color = if (chosen) Color.Black else HudTheme.inkDim), maxLines = 1)
                }
            }
        }
        BasicText("DRAG ONTO THE GLASSES", style = HudTheme.mont(10f, tracking = 2f, color = HudTheme.inkFaint))
        val spare = a.unplaced.filter { it in HudPanelKind.available }
        if (spare.isEmpty()) {
            BasicText("Everything is on the glasses.", style = HudTheme.mont(11f, FontWeight.SemiBold, color = HudTheme.inkFaint))
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (kind in spare) {
                    Box(Modifier.weight(1f).height(58.dp).panelGestures(kind, editor, editing = true, inTray = true)) {
                        MiniChip(kind, if (editor.drag?.first == kind) ChipState.ghost else ChipState.tray, big = true)
                    }
                }
                repeat(4 - spare.size.coerceAtMost(4)) { Spacer(Modifier.weight(1f)) }
            }
        }
        BasicText(if (a.isRow) "Drop on the row to add or replace. Drag one off to remove it. The browser fills the rest."
            else "Drop on a slot to add or replace. Drag one off to remove it. Drop the browser on a side to take that side over.",
            style = HudTheme.mont(10.5f, FontWeight.SemiBold, color = HudTheme.inkFaint))
    }
}

// ------------------------------------------------------------------ tabs

/** The glasses' tabs: tap to switch, the cross to close, the last chip for a new one. */
@Composable
private fun TabStrip() {
    val c = HudController
    val b = c.snapshot.browser
    val view = LocalView.current
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        b.tabs.forEachIndexed { i, title ->
            val active = i == b.activeTab
            Row(Modifier.height(38.dp).background(if (active) Color.White.copy(alpha = 0.10f) else HudTheme.surface),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.fillMaxHeight().clickable { view.tick(); c.perform(PhoneAction.SelectTab(i)) }
                    .padding(start = 12.dp, end = if (b.tabs.size > 1) 0.dp else 12.dp), contentAlignment = Alignment.CenterStart) {
                    BasicText(title, style = HudTheme.mont(11.5f, FontWeight.SemiBold, color = if (active) HudTheme.ink else HudTheme.inkDim),
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(IntrinsicTabWidth(title)))
                }
                if (b.tabs.size > 1) {
                    Box(Modifier.size(32.dp, 38.dp).clickable { view.tick(); c.perform(PhoneAction.CloseTab(i)) }, contentAlignment = Alignment.Center) {
                        Image(Icons.Rounded.Close, null, Modifier.size(13.dp), colorFilter = ColorFilter.tint(if (active) HudTheme.ink else HudTheme.inkDim))
                    }
                }
            }
        }
        val more = b.tabs.size < BrowserMetrics.MAX_TABS
        Box(Modifier.size(38.dp).background(HudTheme.surface).clickable(enabled = more) { view.tick(); c.perform(PhoneAction.NewTab) },
            contentAlignment = Alignment.Center) {
            Image(Icons.Rounded.Add, null, Modifier.size(18.dp), colorFilter = ColorFilter.tint(if (more) HudTheme.ink else HudTheme.inkFaint))
        }
    }
}

private fun IntrinsicTabWidth(title: String) = (title.length * 7).coerceIn(40, 130).dp

// ------------------------------------------------------------------ the pad

/** TOUCHPAD, or the app's own controls when one with controls is alone on the glasses. */
@Composable
private fun PadHeader() {
    val c = HudController
    val view = LocalView.current
    val app = c.solo?.takeIf { it.hasPhoneControls }
    val choices = listOfNotNull(app?.let { PhonePad.app }, PhonePad.touchpad, PhonePad.remote)
    Row(Modifier.fillMaxWidth().height(30.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        for (pad in choices) {
            val on = pad == c.pad || (pad == PhonePad.touchpad && c.pad == PhonePad.app && app == null)
            Column(Modifier.width(IntrinsicSize.Max).clickable { view.tick(); c.perform(PhoneAction.Pad(pad)) }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    if (pad == PhonePad.app && app != null) Image(app.icon, null, Modifier.size(12.dp),
                        colorFilter = ColorFilter.tint(if (on) HudTheme.ink else HudTheme.inkFaint))
                    BasicText(when (pad) { PhonePad.touchpad -> "TOUCHPAD"; PhonePad.remote -> "REMOTE"; PhonePad.app -> app?.padTitle ?: "" },
                        style = HudTheme.mont(11f, tracking = 2f, color = if (on) HudTheme.ink else HudTheme.inkFaint))
                }
                Box(Modifier.padding(top = 3.dp).fillMaxWidth().height(2.5.dp).background(if (on) HudTheme.accent else Color.Transparent, chipShape))
            }
        }
    }
}

/** MiniMate's touchpad, over the halftone: one finger moves, a tap clicks, two scroll, two tap right-click. */
@OptIn(ExperimentalComposeUiApi::class)
@SuppressLint("ClickableViewAccessibility")
@Composable
private fun Touchpad(modifier: Modifier) {
    val context = LocalContext.current
    val view = LocalView.current
    val recognizer = remember {
        GestureRecognizer(context) { event ->
            if (event == GestureEvent.TapClick || event == GestureEvent.RightClick) view.tick()
            HudController.gesture(event)
        }
    }
    Box(modifier
        .onSizeChanged { recognizer.screenWidth = it.width.toFloat(); recognizer.screenHeight = it.height.toFloat() }
        .pointerInteropFilter { recognizer.onTouchEvent(it); true }) {
        HalftoneBackground(Modifier.fillMaxSize())
        if (!HudController.glassesConnected) {
            Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                BasicText("CONNECT THE GLASSES", style = HudTheme.mont(14f, tracking = 2.5f))
                BasicText("Plug them into the phone's USB-C port.",
                    style = HudTheme.mont(13f, FontWeight.SemiBold, color = HudTheme.inkDim))
            }
        }
    }
}

@Composable
private fun AppControls(kind: HudPanelKind) {
    Box(Modifier.fillMaxSize().padding(horizontal = 12.dp).padding(top = 4.dp, bottom = 10.dp)) {
        when (kind) {
            HudPanelKind.clock -> TimerControls(HudController.snapshot.timer)
            HudPanelKind.note -> NoteControls(HudController.snapshot.note)
            HudPanelKind.sky -> SkyControls()
            HudPanelKind.music -> MusicControls()
            HudPanelKind.captions -> CaptionsControls()
            HudPanelKind.youtube -> YouTubeControls()
            HudPanelKind.map -> MapsControls()
            else -> {}
        }
    }
}

@Composable
private fun PadCard(modifier: Modifier, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Box(modifier.clip(shape).background(Color(0xFF171717)).border(1.dp, HudTheme.edge, shape)) { content() }
}

@Composable
private fun PadButton(icon: ImageVector, title: String, modifier: Modifier, lit: Boolean = false, action: () -> Unit) {
    val view = LocalView.current
    Column(modifier.fillMaxHeight().clip(RoundedCornerShape(16.dp)).background(if (lit) HudTheme.accent else Color(0xFF242424))
        .clickable { view.tick(); action() },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        val fg = if (lit) Color.Black else HudTheme.ink
        Image(icon, null, Modifier.size(if (lit) 26.dp else 20.dp), colorFilter = ColorFilter.tint(fg))
        Spacer(Modifier.height(4.dp))
        BasicText(title, style = HudTheme.mont(9f, tracking = 1.6f, color = fg))
    }
}

@Composable
private fun TimerControls(timer: HudSnapshot.TimerReading) {
    val c = HudController
    val view = LocalView.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PadCard(Modifier.fillMaxWidth().weight(1f)) {
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                BasicText(when {
                    timer.isStopwatch -> "STOPWATCH"
                    timer.state == HudSnapshot.TimerState.running -> "RUNNING"
                    timer.state == HudSnapshot.TimerState.paused -> "PAUSED"
                    timer.state == HudSnapshot.TimerState.done -> "DONE"
                    else -> "TIMER"
                }, style = HudTheme.mont(9f, tracking = 2f,
                    color = if (timer.state == HudSnapshot.TimerState.running) HudTheme.accent else HudTheme.inkDim))
                BasicText(timer.text, style = HudTheme.mont(44f))
                timer.progress?.let { p ->
                    Box(Modifier.padding(horizontal = 30.dp, vertical = 2.dp).fillMaxWidth().height(4.dp).background(HudTheme.inkFaint, chipShape)) {
                        Box(Modifier.fillMaxWidth(p).fillMaxHeight().background(HudTheme.accent, chipShape))
                    }
                }
            }
        }
        for (row in listOf(listOf(1, 3, 5, 10), listOf(15, 25, 45, 0))) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (minutes in row) {
                    Box(Modifier.weight(1f).height(28.dp).clip(chipShape).background(Color(0xFF1F1F1F))
                        .clickable { view.tick(); c.perform(PhoneAction.Timer(TimerAction.Set(minutes))) }, contentAlignment = Alignment.Center) {
                        BasicText(if (minutes == 0) "STOPWATCH" else "$minutes MIN", style = HudTheme.mont(8.5f, tracking = 1f, color = HudTheme.inkDim))
                    }
                }
            }
        }
        Row(Modifier.height(64.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PadButton(Icons.Rounded.Refresh, "RESET", Modifier.width(80.dp)) { c.perform(PhoneAction.Timer(TimerAction.Reset)) }
            val running = timer.state == HudSnapshot.TimerState.running
            PadButton(if (running) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, if (running) "PAUSE" else "START",
                Modifier.weight(1f), lit = true) { c.perform(PhoneAction.Timer(TimerAction.Toggle)) }
            PadButton(Icons.Rounded.Add, "1 MIN", Modifier.width(80.dp)) { c.perform(PhoneAction.Timer(TimerAction.Add(1))) }
        }
    }
}

@Composable
private fun NoteControls(note: HudSnapshot.Note) {
    val c = HudController
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Drag to roll the teleprompter on the glasses.
        PadCard(Modifier.fillMaxWidth().weight(1f).pointerInput(Unit) {
            detectVerticalDragGestures { change, dy -> change.consume(); c.perform(PhoneAction.Note(NoteAction.Scroll(-dy / density * 3))) }
        }) {
            Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                BasicText(if (note.isEditing) "WRITING" else "TELEPROMPTER",
                    style = HudTheme.mont(9f, tracking = 2f, color = if (note.isEditing) HudTheme.accent else HudTheme.inkDim))
                BasicText(note.text.ifEmpty { "Nothing written yet" },
                    style = HudTheme.mont(14f, FontWeight.SemiBold, color = if (note.text.isEmpty()) HudTheme.inkFaint else HudTheme.ink),
                    overflow = TextOverflow.Clip)
            }
        }
        Row(Modifier.height(64.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PadButton(Icons.Rounded.DeleteOutline, "CLEAR", Modifier.width(80.dp)) { c.perform(PhoneAction.Note(NoteAction.Clear)) }
            PadButton(if (note.isEditing) Icons.Rounded.Check else Icons.Rounded.Edit, if (note.isEditing) "DONE" else "WRITE",
                Modifier.weight(1f), lit = true) { c.perform(PhoneAction.Note(NoteAction.Write)) }
            PadButton(Icons.Rounded.VerticalAlignTop, "TOP", Modifier.width(80.dp)) {
                c.perform(PhoneAction.Note(NoteAction.Scroll(Float.NEGATIVE_INFINITY)))
            }
        }
    }
}

// ------------------------------------------------------------------ settings

@Composable
private fun SettingsPage() {
    val c = HudController
    val context = LocalContext.current
    val view = LocalView.current
    val display = GlassesPresenter.shownDisplay
    @Suppress("UNUSED_VARIABLE") val version = c.settingsVersion
    val sessions = remember(version) { CaptionsLog.sessions(context) }
    fun open(intent: Intent) = runCatching { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    LazyColumn(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item { SettingsTitle("GLASSES") }
        item {
            BasicText(display?.let { "${it.name} · ${it.mode.physicalWidth}×${it.mode.physicalHeight}" } ?: "Not connected",
                style = HudTheme.mont(15f, FontWeight.SemiBold))
        }
        item { SettingsTitle("TRACKPAD") }
        item {
            SettingsStepper("Speed", "%.1f×".format(c.trackpadSpeed),
                { c.changeTrackpadSpeed(c.trackpadSpeed - 0.1f) }, { c.changeTrackpadSpeed(c.trackpadSpeed + 0.1f) })
        }
        item { SettingsTitle("ACTIVITY") }
        item { SettingsStepper("Daily goal", "%,d steps".format(c.stepGoal), { c.changeStepGoal(c.stepGoal - 500) }, { c.changeStepGoal(c.stepGoal + 500) }) }
        item { SettingsTitle("CAPTIONS") }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for ((tag, name) in CaptionsEngine.languages) {
                    val on = tag == c.captionsLanguage
                    Box(Modifier.height(30.dp).clip(chipShape).background(if (on) HudTheme.accent else Color(0xFF1F1F1F))
                        .clickable { view.tick(); c.changeCaptionsLanguage(tag) }.padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                        BasicText(name, style = HudTheme.mont(10f, FontWeight.SemiBold, color = if (on) Color.Black else HudTheme.inkDim))
                    }
                }
            }
        }
        if (sessions.isEmpty()) item { SettingsNote("Every captions session is saved here as a text file.") }
        items(sessions.take(20), key = { it.file.path }) { session ->
            Row(Modifier.fillMaxWidth().clip(tileShape).background(Color(0xFF171717)).padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    BasicText(java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT).format(java.util.Date(session.date)) +
                        " · ${session.lines} lines", style = HudTheme.mont(11f, FontWeight.SemiBold))
                    BasicText(session.preview, style = HudTheme.mont(10f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                BasicText("SHARE", style = HudTheme.mont(9f, tracking = 1.5f, color = HudTheme.accent), modifier = Modifier.padding(horizontal = 8.dp).clickable {
                    runCatching {
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, session.file.readText())
                        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                })
                BasicText("DELETE", style = HudTheme.mont(9f, tracking = 1.5f, color = HudTheme.inkDim), modifier = Modifier.clickable {
                    CaptionsLog.delete(session); c.captionSessionsChanged()
                })
            }
        }
        item { SettingsTitle("YOUTUBE") }
        item {
            SettingsToggle("Subscriptions tab", c.youtubeSubscriptions) { c.changeYouTubeSubscriptions(!c.youtubeSubscriptions) }
            SettingsNote("Signed in through the browser on the glasses: open youtube.com there and sign in, and Home and Subscriptions are yours.")
        }
        item { SettingsTitle("ACCESS") }
        item {
            SettingsLink("Now Playing", if (c.musicAllowed) "ON" else "NOTIFICATION ACCESS") {
                open(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
        }
        item {
            SettingsLink("Android apps on the glasses", if (c.appsServiceEnabled) "ON" else "ACCESSIBILITY") { c.openAccessibilitySettings() }
        }
        item {
            SettingsLink("Location, microphone, steps, calendar", "APP SETTINGS") {
                open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", context.packageName, null)))
            }
        }
        item { SettingsTitle("HOW IT WORKS") }
        item {
            SettingsNote("Tap GLASSES to clear the view; hold it to arrange. Tap a panel to switch it off or on; hold it to show it alone. " +
                "Hold a scene to put it back as it was. Switch the lower half between TOUCHPAD, REMOTE and the app's own controls above it.")
        }
        item {
            SettingsNote("Routes are worked out by routing.openstreetmap.de from where you are, to about ten metres. Searches, weather and " +
                "the sky's aircraft only get your position rounded to a kilometre or so.")
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun SettingsTitle(text: String) {
    BasicText(text, style = HudTheme.mont(11f, tracking = 2.5f, color = HudTheme.inkDim), modifier = Modifier.padding(top = 10.dp))
}

@Composable
private fun SettingsNote(text: String) {
    BasicText(text, style = HudTheme.mont(11f, FontWeight.SemiBold, color = HudTheme.inkDim))
}

@Composable
private fun SettingsStepper(title: String, value: String, minus: () -> Unit, plus: () -> Unit) {
    val view = LocalView.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        BasicText(title, style = HudTheme.mont(13f, FontWeight.SemiBold), modifier = Modifier.weight(1f))
        for ((label, act) in listOf("−" to minus)) Box(Modifier.size(34.dp).clip(chipShape).background(Color(0xFF242424)).clickable { view.tick(); act() },
            contentAlignment = Alignment.Center) { BasicText(label, style = HudTheme.mont(16f)) }
        BasicText(value, style = HudTheme.mont(12f), modifier = Modifier.width(92.dp), maxLines = 1)
        Box(Modifier.size(34.dp).clip(chipShape).background(Color(0xFF242424)).clickable { view.tick(); plus() },
            contentAlignment = Alignment.Center) { BasicText("+", style = HudTheme.mont(16f)) }
    }
}

@Composable
private fun SettingsToggle(title: String, on: Boolean, toggle: () -> Unit) {
    val view = LocalView.current
    Row(Modifier.fillMaxWidth().clickable { view.tick(); toggle() }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        BasicText(title, style = HudTheme.mont(13f, FontWeight.SemiBold), modifier = Modifier.weight(1f))
        Box(Modifier.size(44.dp, 26.dp).clip(chipShape).background(if (on) HudTheme.accent else Color(0xFF333333))) {
            Box(Modifier.padding(3.dp).size(20.dp).align(if (on) Alignment.CenterEnd else Alignment.CenterStart).background(Color.White, chipShape))
        }
    }
}

@Composable
private fun SettingsLink(title: String, value: String, action: () -> Unit) {
    val view = LocalView.current
    Row(Modifier.fillMaxWidth().clip(tileShape).background(Color(0xFF171717)).clickable { view.tick(); action() }.padding(12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        BasicText(title, style = HudTheme.mont(12f, FontWeight.SemiBold), modifier = Modifier.weight(1f))
        BasicText(value, style = HudTheme.mont(9f, tracking = 1.5f, color = if (value == "ON") HudTheme.accent else HudTheme.inkDim))
    }
}

// ------------------------------------------------------------------ the keyboard

/**
 * Invisible but focusable: the app draws no keyboard of its own, it asks for the phone's, and
 * what is typed goes on to the address bar, the page or the note, as on the iPhone.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun KeyboardProxy() {
    val c = HudController
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val target = c.keyboardTarget
    var wasUp by remember { mutableStateOf(false) }
    val imeUp = WindowInsets.isImeVisible

    // The field keeps the keyboard's own selection and the word it is composing; when the
    // controller changes the text itself (a new target, the page's sentinel put back), the
    // cursor goes to the end, which is where everything is typed.
    var field by remember { mutableStateOf(TextFieldValue()) }
    val shown = if (field.text == c.draft) field else TextFieldValue(c.draft, TextRange(c.draft.length))

    BasicTextField(
        value = shown,
        onValueChange = { v -> field = v; c.draftChanged(v.text) },
        singleLine = target != KeyboardTarget.note,
        keyboardOptions = KeyboardOptions(
            capitalization = if (target == KeyboardTarget.address || target == KeyboardTarget.mac) KeyboardCapitalization.None
                else KeyboardCapitalization.Sentences,
            autoCorrectEnabled = target != KeyboardTarget.address && target != KeyboardTarget.mac,
            keyboardType = if (target == KeyboardTarget.address) KeyboardType.Uri else KeyboardType.Text,
            imeAction = when (target) {
                KeyboardTarget.address -> ImeAction.Go
                KeyboardTarget.note -> ImeAction.Default
                KeyboardTarget.mapSearch, KeyboardTarget.youtubeSearch -> ImeAction.Search
                else -> ImeAction.Send
            },
        ),
        keyboardActions = KeyboardActions(onGo = { c.submitTyping() }, onSend = { c.submitTyping() }, onSearch = { c.submitTyping() }),
        modifier = Modifier.size(1.dp).alpha(0f).focusRequester(focus),
    )

    LaunchedEffect(target) {
        if (target != null) { focus.requestFocus(); keyboard?.show() } else { keyboard?.hide(); focus.freeFocus() }
    }
    // The keyboard put away by hand ends the typing, as on the iPhone.
    LaunchedEffect(imeUp) {
        if (wasUp && !imeUp && c.keyboardTarget != null) c.endTyping()
        wasUp = imeUp
    }
}
