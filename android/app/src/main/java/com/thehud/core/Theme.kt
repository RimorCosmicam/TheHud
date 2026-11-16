package com.thehud.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import kotlin.math.atan2
import kotlin.math.cbrt
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The app's one colour, as on the iPhone: the accent everywhere, the touchpad's halftone, and the
 * launcher icon.
 *
 * Every theme is the mustard turned round the colour wheel in OKLCH, which keeps the perceived
 * lightness, so each colour reads on the dark app as the mustard does: bright marks on black, black
 * text on an accent chip. The same numbers as the iPhone's `ThemeColor`, so both phones match.
 */
enum class ThemeColor(val shift: Double) {
    mustard(0.0), lime(40.0), mint(90.0), sky(150.0), iris(200.0), orchid(245.0), rose(280.0), coral(315.0);

    val title: String get() = name.replaceFirstChar { it.uppercase() }

    /** Any colour of the mustard theme, in this one. ARGB, alpha kept. */
    fun color(argb: Long): Color = Color(OKLCH.rotate(argb, shift))

    val accent: Color get() = color(0xFFD8A628)

    companion object {
        fun named(name: String?): ThemeColor? = entries.firstOrNull { it.name == name }
    }
}

/** The chosen theme, as Compose state: whatever reads `HudTheme.accent` redraws when it changes. */
object ThemeState {
    var color by mutableStateOf(ThemeColor.mustard)
    val accent: Color get() = accents[color.ordinal]
    private val accents = ThemeColor.entries.map { it.accent }
}

/** OKLab (Björn Ottosson's), for turning a colour's hue while keeping how light it looks. */
object OKLCH {
    fun rotate(argb: Long, degrees: Double): Long {
        if (degrees == 0.0) return argb
        val (l0, a0, b0) = lab(argb)
        val chroma = sqrt(a0 * a0 + b0 * b0)
        if (chroma < 1e-4) return argb
        val hue = atan2(b0, a0) + degrees * Math.PI / 180
        var lo = 0.0
        var hi = 1.0
        if (inGamut(rgb(l0, chroma * cos(hue), chroma * sin(hue)))) lo = 1.0
        else repeat(24) {
            val k = (lo + hi) / 2
            if (inGamut(rgb(l0, chroma * k * cos(hue), chroma * k * sin(hue)))) lo = k else hi = k
        }
        val c = rgb(l0, chroma * lo * cos(hue), chroma * lo * sin(hue))
        return (argb and 0xFF000000) or (byte(c[0]) shl 16) or (byte(c[1]) shl 8) or byte(c[2])
    }

    private fun lab(argb: Long): DoubleArray {
        val r = linear(((argb shr 16) and 0xFF) / 255.0)
        val g = linear(((argb shr 8) and 0xFF) / 255.0)
        val b = linear((argb and 0xFF) / 255.0)
        val l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        val m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        val s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return doubleArrayOf(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private operator fun DoubleArray.component1() = this[0]
    private operator fun DoubleArray.component2() = this[1]
    private operator fun DoubleArray.component3() = this[2]

    private fun rgb(L: Double, a: Double, b: Double): DoubleArray {
        val l = (L + 0.3963377774 * a + 0.2158037573 * b).pow(3)
        val m = (L - 0.1055613458 * a - 0.0638541728 * b).pow(3)
        val s = (L - 0.0894841775 * a - 1.2914855480 * b).pow(3)
        return doubleArrayOf(
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private fun inGamut(c: DoubleArray) = c.all { it >= -1e-4 && it <= 1 + 1e-4 }

    private fun linear(c: Double) = if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)

    private fun byte(linear: Double): Long {
        val c = linear.coerceIn(0.0, 1.0)
        val s = if (c <= 0.0031308) 12.92 * c else 1.055 * c.pow(1 / 2.4) - 0.055
        return Math.round(s * 255)
    }
}
