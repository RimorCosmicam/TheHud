package com.thehud.core

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.thehud.R

/**
 * MiniMate's "Mont" panel material, as on the iPhone: black at ninety-two percent, Mont in white,
 * state carried by brightness alone, one gold accent.
 *
 * On the glasses one dp is one point of the 1920x1080 canvas (the glasses window sets its density
 * so), which keeps every number here the same as the iPhone app's.
 */
object HudTheme {
    const val CANVAS_WIDTH = 1920f
    const val CANVAS_HEIGHT = 1080f
    const val SAFE_INSET = 64f
    const val CORNER = 28f

    const val SURFACE_ALPHA = 0.92f
    val surface = Color.Black.copy(alpha = SURFACE_ALPHA)
    val ink = Color.White
    val inkDim = Color.White.copy(alpha = 0.55f)
    val inkFaint = Color.White.copy(alpha = 0.28f)
    val accent = Color(0xFFD8A628)
    val edge = Color.White.copy(alpha = 0.09f)

    val mont = FontFamily(
        Font(R.font.mont_thin, FontWeight.Thin),
        Font(R.font.mont_light, FontWeight.Light),
        Font(R.font.mont_regular, FontWeight.Normal),
        Font(R.font.mont_semibold, FontWeight.SemiBold),
        Font(R.font.mont_black, FontWeight.Black),
    )

    /** Mont at a size in points, with tracking in points as SwiftUI's `tracking` takes it. */
    fun mont(size: Float, weight: FontWeight = FontWeight.Black, tracking: Float = 0f, color: Color = ink): TextStyle =
        TextStyle(
            fontFamily = mont, fontWeight = weight, fontSize = size.sp, color = color,
            letterSpacing = if (tracking == 0f) TextUnit.Unspecified else (tracking / size).em,
            lineHeight = (size * 1.18f).sp,
        )
}
