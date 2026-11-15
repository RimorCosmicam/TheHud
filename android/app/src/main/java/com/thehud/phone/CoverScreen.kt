package com.thehud.phone

import android.annotation.SuppressLint
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.KeyboardHide
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.StickyNote2
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.thehud.HudController
import com.thehud.KeyboardTarget
import com.thehud.PhoneAction
import com.thehud.core.HudPanelKind
import com.thehud.core.HudTheme
import com.thehud.glasses.GlassesPresenter
import com.thehud.glasses.GlassesScreen
import com.thehud.touchpad.GestureEvent
import com.thehud.touchpad.GestureRecognizer
import com.thehud.ui.HalftoneBackground

// The Flip's cover screen, about 400 by 440 points with the cameras in its lower right corner:
// the buttons along the top, the glasses in miniature with the scenes, and the rest is touchpad.

private val chipShape = RoundedCornerShape(50)

@Composable
fun CoverScreen() {
    val c = HudController
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        // The pad runs to the bottom edge: the cameras simply sit over a corner of it.
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
            ToolBar()
            if (c.showingSettings) {
                SettingsPage()
            } else {
                Overview()
                Touchpad(Modifier.weight(1f).fillMaxWidth())
            }
        }
        KeyboardProxy()
    }
}

// ------------------------------------------------------------------ the buttons

@Composable
private fun ToolBar() {
    val c = HudController
    val b = c.snapshot.browser
    Row(Modifier.fillMaxWidth().height(50.dp).padding(horizontal = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        ToolButton(Icons.Rounded.ChevronLeft, enabled = b.canGoBack) { c.perform(PhoneAction.Back) }
        ToolButton(Icons.Rounded.ChevronRight, enabled = b.canGoForward) { c.perform(PhoneAction.Forward) }
        ToolButton(Icons.Rounded.Refresh) { c.perform(PhoneAction.Reload) }
        ToolButton(Icons.Rounded.Search, lit = c.keyboardTarget == KeyboardTarget.address) { c.perform(PhoneAction.Address) }
        ToolButton(if (c.keyboardTarget != null) Icons.Rounded.KeyboardHide else Icons.Rounded.Keyboard,
            lit = c.keyboardTarget != null) { c.perform(PhoneAction.Keyboard) }
        ToolButton(Icons.Rounded.VisibilityOff, lit = c.clearView) { c.perform(PhoneAction.ClearView) }
        ToolButton(Icons.Rounded.Settings, lit = c.showingSettings) { c.showingSettings = !c.showingSettings }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ToolButton(icon: ImageVector, enabled: Boolean = true, lit: Boolean = false, onLong: (() -> Unit)? = null, action: () -> Unit) {
    val view = LocalView.current
    Box(Modifier.size(46.dp).clip(chipShape)
        .background(if (lit) Color.White.copy(alpha = 0.16f) else Color.Transparent)
        .combinedClickable(enabled = enabled, onLongClick = onLong?.let { long -> {
            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS); long() } }) {
            view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK); action() },
        contentAlignment = Alignment.Center) {
        Image(icon, null, Modifier.size(28.dp),
            colorFilter = ColorFilter.tint(when { lit -> HudTheme.accent; enabled -> HudTheme.ink; else -> HudTheme.inkFaint }))
    }
}

// ------------------------------------------------------------------ the glasses in small

private fun HudPanelKind.icon(): ImageVector = when (this) {
    HudPanelKind.browser -> Icons.Rounded.Language
    HudPanelKind.clock -> Icons.Rounded.Schedule
    HudPanelKind.weather -> Icons.Rounded.Cloud
    else -> Icons.Rounded.StickyNote2
}

/**
 * The glasses as they are, small, beside the scenes and a button for each panel: tap one to show
 * or hide it, hold it to have it alone.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Overview() {
    val c = HudController
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Miniature(Modifier.width(168.dp))
        Spacer(Modifier.width(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                c.scenes.forEachIndexed { i, scene ->
                    Chip(scene.name, lit = i == c.sceneIndex && c.solo == null && !c.clearView) { c.perform(PhoneAction.Scene(i)) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val view = LocalView.current
                for (kind in listOf(HudPanelKind.browser, HudPanelKind.clock, HudPanelKind.weather, HudPanelKind.note)) {
                    val on = c.isOnGlasses(kind)
                    Box(Modifier.size(44.dp).clip(chipShape)
                        .background(if (on) Color.White.copy(alpha = 0.16f) else Color.Transparent)
                        .border(1.dp, if (c.solo == kind) HudTheme.accent else HudTheme.edge, chipShape)
                        .combinedClickable(onLongClick = {
                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            c.perform(PhoneAction.Solo(kind))
                        }) {
                            view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                            c.perform(PhoneAction.TapPanel(kind))
                        }, contentAlignment = Alignment.Center) {
                        Image(kind.icon(), null, Modifier.size(24.dp),
                            colorFilter = ColorFilter.tint(if (on) HudTheme.ink else HudTheme.inkFaint))
                    }
                }
            }
        }
    }
}

@Composable
private fun Chip(text: String, lit: Boolean, action: () -> Unit) {
    val view = LocalView.current
    Box(Modifier.height(32.dp).clip(chipShape)
        .background(if (lit) HudTheme.ink else Color.White.copy(alpha = 0.08f))
        .combinedClickableCompat { view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK); action() }
        .padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
        BasicText(text, style = HudTheme.mont(11f, tracking = 1.2f, color = if (lit) Color.Black else HudTheme.inkDim))
    }
}

@OptIn(ExperimentalFoundationApi::class)
private fun Modifier.combinedClickableCompat(action: () -> Unit) = this.combinedClickable(onClick = action)

/** The very picture the glasses get, drawn small; the page is left out, it is on the glasses. */
@Composable
fun Miniature(modifier: Modifier) {
    val c = HudController
    BoxWithConstraints(modifier.height(94.dp).clip(RoundedCornerShape(10.dp))
        .border(1.dp, if (c.glassesConnected) HudTheme.edge else HudTheme.inkFaint, RoundedCornerShape(10.dp)),
        contentAlignment = Alignment.Center) {
        val scale = constraints.maxWidth / HudTheme.CANVAS_WIDTH
        CompositionLocalProvider(LocalDensity provides Density(scale, 1f)) {
            Box(Modifier.requiredSize(HudTheme.CANVAS_WIDTH.dp, HudTheme.CANVAS_HEIGHT.dp)) {
                GlassesScreen(c.snapshot.copy(cursor = c.snapshot.cursor), c.layout, page = {
                    Box(Modifier.fillMaxSize().background(Color(0xFF121214)))
                })
            }
        }
        if (!c.glassesConnected) {
            BasicText("NO GLASSES", style = HudTheme.mont(10f, tracking = 2f, color = HudTheme.inkDim),
                modifier = Modifier.background(Color.Black.copy(alpha = 0.7f), chipShape).padding(horizontal = 8.dp, vertical = 3.dp))
        }
    }
}

// ------------------------------------------------------------------ the pad

/** MiniMate's touchpad, over the halftone: one finger moves, a tap clicks, two scroll, two tap right-click. */
@OptIn(ExperimentalComposeUiApi::class)
@SuppressLint("ClickableViewAccessibility")
@Composable
private fun Touchpad(modifier: Modifier) {
    val context = LocalContext.current
    val view = LocalView.current
    val recognizer = remember {
        GestureRecognizer(context) { event ->
            if (event == GestureEvent.TapClick || event == GestureEvent.RightClick) {
                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
            }
            HudController.gesture(event)
        }
    }
    Box(modifier.padding(top = 6.dp)
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

// ------------------------------------------------------------------ settings

@Composable
private fun SettingsPage() {
    val c = HudController
    val display = GlassesPresenter.shownDisplay
    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        BasicText("GLASSES", style = HudTheme.mont(12f, tracking = 2.5f, color = HudTheme.inkDim))
        BasicText(display?.let { "${it.name} · display ${it.displayId} · ${it.mode.physicalWidth}×${it.mode.physicalHeight}" }
            ?: "Not connected", style = HudTheme.mont(16f, FontWeight.SemiBold))
        BasicText("LAYOUT", style = HudTheme.mont(12f, tracking = 2.5f, color = HudTheme.inkDim))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip("COLUMNS", lit = c.arrangement.strip == null) { c.perform(PhoneAction.Layout(null)) }
            Chip("ROW ON TOP", lit = c.arrangement.strip == com.thehud.core.HudEdge.top) { c.perform(PhoneAction.Layout(com.thehud.core.HudEdge.top)) }
            Chip("BOTTOM", lit = c.arrangement.strip == com.thehud.core.HudEdge.bottom) { c.perform(PhoneAction.Layout(com.thehud.core.HudEdge.bottom)) }
        }
        BasicText("SCENE", style = HudTheme.mont(12f, tracking = 2.5f, color = HudTheme.inkDim))
        Chip("RESET ${c.scenes[c.sceneIndex].name}", lit = false) { c.perform(PhoneAction.ResetScene(c.sceneIndex)) }
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

    BasicTextField(
        value = c.draft,
        onValueChange = c::draftChanged,
        singleLine = target != KeyboardTarget.note,
        keyboardOptions = KeyboardOptions(
            capitalization = if (target == KeyboardTarget.address) KeyboardCapitalization.None else KeyboardCapitalization.Sentences,
            autoCorrectEnabled = target != KeyboardTarget.address,
            keyboardType = if (target == KeyboardTarget.address) KeyboardType.Uri else KeyboardType.Text,
            imeAction = when (target) { KeyboardTarget.address -> ImeAction.Go; KeyboardTarget.note -> ImeAction.Default; else -> ImeAction.Send },
        ),
        keyboardActions = KeyboardActions(onGo = { c.submitTyping() }, onSend = { c.submitTyping() }),
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
