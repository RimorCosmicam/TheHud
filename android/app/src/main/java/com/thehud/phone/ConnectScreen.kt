package com.thehud.phone

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.thehud.HudController
import com.thehud.core.HudTheme

/**
 * Remote Connect's pairing screen: the code the iPhone scans to work these glasses. It closes on
 * its own once the iPhone is in.
 */
@Composable
fun ConnectScreen() {
    val c = HudController
    BackHandler { c.showingConnect = false }
    Box(Modifier.fillMaxSize().background(Color.Black)
        // Nothing underneath takes a touch while this is up.
        .clickable(remember { MutableInteractionSource() }, indication = null) {},
        contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 360.dp).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            BasicText("REMOTE CONNECT", style = HudTheme.mont(13f, tracking = 3f))
            val matrix = remember(c.connectLink) { qr(c.connectLink) }
            // Dark modules on white, with the quiet zone the camera needs.
            Box(Modifier.size(240.dp).background(Color.White, RoundedCornerShape(14.dp)).padding(16.dp)) {
                if (matrix != null) QrCode(matrix, Modifier.fillMaxSize())
            }
            val status = when {
                c.remotePeer != null -> "${c.remotePeer!!.uppercase()} IS CONNECTED"
                c.connectLink.contains("&h=&") -> "JOIN A WI-FI NETWORK FIRST"
                else -> "SCAN WITH THE HUD ON YOUR IPHONE: HOLD ITS SETTINGS BUTTON"
            }
            BasicText(status, style = HudTheme.mont(11f, tracking = 1.5f, color = HudTheme.inkDim).copy(textAlign = TextAlign.Center))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ConnectButton("NEW CODE", Modifier.weight(1f)) { c.newConnectCode() }
                ConnectButton("CLOSE", Modifier.weight(1f)) { c.showingConnect = false }
            }
        }
    }
}

/** Host mode, on the cover screen: the glasses show the iPhone, which works them. */
@Composable
fun HostedScreen() {
    val c = HudController
    Box(Modifier.fillMaxSize().background(Color.Black)
        .clickable(remember { MutableInteractionSource() }, indication = null) {},
        contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 360.dp).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            BasicText("HOST MODE", style = HudTheme.mont(13f, tracking = 3f, color = HudTheme.accent))
            BasicText("THE GLASSES SHOW ${(c.remotePeer ?: "the iPhone").uppercase()}",
                style = HudTheme.mont(16f, tracking = 1.5f).copy(textAlign = TextAlign.Center))
            BasicText("Its apps run there: work them from the iPhone. Switch it to Remote, or disconnect it, to have this phone's apps back.",
                style = HudTheme.mont(12f, color = HudTheme.inkDim).copy(textAlign = TextAlign.Center))
            ConnectButton("REMOTE CONNECT", Modifier.fillMaxWidth()) { c.showConnect() }
        }
    }
}

@Composable
private fun ConnectButton(title: String, modifier: Modifier, action: () -> Unit) {
    Box(modifier.height(44.dp).border(1.dp, HudTheme.inkFaint, RoundedCornerShape(10.dp)).clickable { action() },
        contentAlignment = Alignment.Center) {
        BasicText(title, style = HudTheme.mont(11f, tracking = 2f))
    }
}

@Composable
private fun QrCode(matrix: BitMatrix, modifier: Modifier) {
    Canvas(modifier) {
        val cell = size.minDimension / matrix.width
        for (y in 0 until matrix.height) for (x in 0 until matrix.width) {
            if (matrix[x, y]) drawRect(Color.Black, Offset(x * cell, y * cell), Size(cell + 0.5f, cell + 0.5f))
        }
    }
}

private fun qr(text: String): BitMatrix? = if (text.isEmpty()) null else runCatching {
    QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0,
        mapOf(EncodeHintType.MARGIN to 0, EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M))
}.getOrNull()
