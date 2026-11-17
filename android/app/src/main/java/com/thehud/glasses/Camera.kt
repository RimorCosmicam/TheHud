package com.thehud.glasses

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FlashlightOn
import androidx.compose.material.icons.rounded.PauseCircle
import androidx.compose.material.icons.rounded.VideocamOff
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import kotlinx.coroutines.delay

// The camera on the glasses, as HudCamera.swift draws it: the phone's picture (the device's), and
// over it the mode, the zoom, recording, a flash for each photo, or a card when it is not running.

private val recRed = Color(0xFFFF453A)
private val shade = Shadow(Color.Black.copy(alpha = 0.8f), Offset.Zero, 12f)

@Composable
private fun CameraView(camera: HudSnapshot.Camera, content: (@Composable (Boolean) -> Unit)?, standIn: Boolean,
                       fill: Boolean, compact: Boolean) {
    Box(Modifier.fillMaxSize().background(Color.Black).clipToBounds()) {
        if (camera.status == HudSnapshot.Camera.Status.running) {
            if (content != null) content(fill) else if (standIn) CameraStandIn()
            Marks(camera, compact)
        } else Card(camera.status, compact)
        Flash(camera.shotAt)
    }
}

@Composable
private fun Marks(camera: HudSnapshot.Camera, compact: Boolean) {
    val pad = if (compact) 20.dp else 36.dp
    val size = if (compact) 15f else 20f
    Box(Modifier.fillMaxSize().padding(pad)) {
        Row(Modifier.align(Alignment.TopStart), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            val since = camera.recordingSince
            if (since != null) {
                Box(Modifier.size((size * 0.7f).dp).background(recRed, CircleShape))
                BasicText(duration(clock(500) - since), style = HudTheme.mont(size, tracking = 2.5f).copy(shadow = shade))
            } else {
                BasicText(camera.mode.title, style = HudTheme.mont(size, tracking = 2.5f,
                    color = if (camera.mode == HudSnapshot.Camera.Mode.magnify) HudTheme.accent else HudTheme.ink).copy(shadow = shade))
            }
            if (camera.frozen) BasicText("FROZEN", style = HudTheme.mont(size, tracking = 2.5f, color = Color.Black),
                modifier = Modifier.background(HudTheme.accent, RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 4.dp))
            if (camera.light) HudIcon(Icons.Rounded.FlashlightOn, size * 1.2f)
            if (camera.bright && camera.mode == HudSnapshot.Camera.Mode.magnify) HudIcon(Icons.Rounded.WbSunny, size * 1.2f)
        }
        Row(Modifier.align(Alignment.BottomStart).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (camera.notice.isNotEmpty() && !compact)
                BasicText(camera.notice, style = HudTheme.mont(size, tracking = 2f).copy(shadow = shade))
            Spacer(Modifier.weight(1f))
            BasicText(camera.zoomTitle, style = HudTheme.mont(if (compact) 18f else 26f,
                color = if (camera.zoom > 1.01) HudTheme.accent else HudTheme.ink).copy(shadow = shade))
        }
    }
}

@Composable
private fun Card(status: HudSnapshot.Camera.Status, compact: Boolean) {
    val paused = status == HudSnapshot.Camera.Status.paused
    val title = if (paused) "CAMERA PAUSED" else "NO CAMERA"
    val line = when (status) {
        HudSnapshot.Camera.Status.paused -> "Open TheHud on the phone to see through it"
        HudSnapshot.Camera.Status.denied -> "Allow the camera for TheHud in Settings"
        else -> "This phone has no camera to open"
    }
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 16.dp, Alignment.CenterVertically)) {
        HudIcon(if (paused) Icons.Rounded.PauseCircle else Icons.Rounded.VideocamOff, if (compact) 34f else 54f, HudTheme.accent)
        BasicText(title, style = HudTheme.mont(if (compact) 18f else 28f, tracking = 3f))
        if (!compact) BasicText(line, style = HudTheme.mont(22f, FontWeight.SemiBold, color = HudTheme.inkDim)
            .copy(textAlign = TextAlign.Center))
    }
}

/** White, fading, for a moment after each photo. */
@Composable
private fun Flash(shotAt: Long) {
    val since by produceState(Long.MAX_VALUE, shotAt) {
        while (true) {
            value = System.currentTimeMillis() - shotAt
            if (value > 400) break
            delay(16)
        }
    }
    if (since < 350) Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.8f * (1 - since / 350f))))
}

/** The wall clock, every so often. */
@Composable
private fun clock(everyMillis: Long): Long {
    val now by produceState(System.currentTimeMillis()) {
        while (true) { delay(everyMillis); value = System.currentTimeMillis() }
    }
    return now
}

internal fun duration(millis: Long): String {
    val s = (millis / 1000).coerceAtLeast(0)
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%02d:%02d".format(s / 60, s % 60)
}

/** The stills' picture: a dim room through a lens. */
@Composable
private fun CameraStandIn() {
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF292E38), Color(0xFF0F0F14))))) {
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Color(0x59F2C780), Color.Transparent),
            center = Offset(1340f, 320f), radius = 520f)))
    }
}

/** A widget: the picture filling the slot. */
@Composable
fun CameraWidget(camera: HudSnapshot.Camera, content: (@Composable (Boolean) -> Unit)?, standIn: Boolean) {
    Box(Modifier.fillMaxSize().clip(panelShape).border(1.dp, HudTheme.edge, panelShape)) {
        CameraView(camera, content, standIn, fill = true, compact = true)
    }
}

/** The centre, or fullscreen edge to edge: the whole picture, fitted. */
@Composable
fun CameraApp(camera: HudSnapshot.Camera, content: (@Composable (Boolean) -> Unit)?, standIn: Boolean, corner: Float) {
    Box(Modifier.fillMaxSize().clip(RoundedCornerShape(corner.dp))) {
        CameraView(camera, content, standIn, fill = false, compact = false)
    }
}
