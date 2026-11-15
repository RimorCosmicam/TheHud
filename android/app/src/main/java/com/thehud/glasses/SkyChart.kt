package com.thehud.glasses

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Flight
import androidx.compose.material.icons.rounded.WbTwilight
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import com.thehud.core.SkyLayer
import com.thehud.core.SkyModel
import com.thehud.core.SkyProjection
import com.thehud.core.SkyTarget
import com.thehud.core.SkyView
import com.thehud.core.Zodiac
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

// The sky held up alone: a chart of what is overhead in the direction the phone faces, as
// SkyChart.swift draws it.

private val stationColour = Color(0.55f, 0.86f, 1f)

private fun starColour(bv: Float): Color {
    val t = ((bv + 0.3f) / 2f).coerceIn(0f, 1f)
    return Color(0.78f + 0.22f * t, 0.86f - 0.06f * t, 1f - 0.4f * t)
}

private fun planetColour(name: String) = when (name) {
    "MARS" -> Color(1f, 0.55f, 0.42f); "JUPITER" -> Color(1f, 0.88f, 0.7f); "SATURN" -> Color(0.95f, 0.8f, 0.5f)
    "VENUS" -> Color(1f, 1f, 0.9f); else -> Color(0.85f, 0.85f, 0.85f)
}

fun skyFacing(heading: Double, view: SkyView) = (((heading + view.pan) % 360) + 360) % 360

@Composable
fun SkyApp(sky: HudSnapshot.Sky, overhead: HudSnapshot.Overhead, view: SkyView, heading: () -> Double) {
    val facing = { skyFacing(heading(), view) }
    val selected = view.selected?.let { id -> SkyTarget.all(sky, overhead, view.layers).firstOrNull { it.id == id } }
    Box(Modifier.size(HudTheme.CANVAS_WIDTH.dp, HudTheme.CANVAS_HEIGHT.dp)) {
        SkyCanvas(sky, overhead, view.layers, { SkyProjection(facing(), view.fov, view.tilt) }, view.fov, selected)
        Box(Modifier.size(1100.dp, 700.dp).background(Brush.radialGradient(
            0f to Color.Black.copy(alpha = 0.85f), 0.19f to Color.Black.copy(alpha = 0.85f), 1f to Color.Transparent,
            center = Offset.Zero, radius = 640f)))
        Column(Modifier.at(Rect(72f, 52f, 972f, 292f)), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                SkyBearing(facing)
                if (view.isAdjusted) BasicText("${view.fov.roundToInt()}° WIDE", style = HudTheme.mont(16f, tracking = 2.5f, color = HudTheme.inkFaint),
                    modifier = Modifier.padding(bottom = 12.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(26.dp), verticalAlignment = Alignment.CenterVertically) {
                val sun = if (sky.sunset != null && sky.sunAltitude > -1) "SETS ${sky.sunset}" else sky.sunrise?.let { "RISES $it" }
                sun?.let { Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    HudIcon(Icons.Rounded.WbTwilight, 22f, HudTheme.inkDim)
                    BasicText(it, style = HudTheme.mont(17f, tracking = 2.5f, color = HudTheme.inkDim))
                } }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MoonGlyph(sky.moonPhaseIndex, Modifier.size(22.dp), HudTheme.inkDim)
                    BasicText("${sky.moonPhase} · ${sky.moonIllumination}%", style = HudTheme.mont(17f, tracking = 2.5f, color = HudTheme.inkDim))
                }
            }
            if (SkyLayer.zodiac in view.layers && sky.sunSign != null && sky.moonSign != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(26.dp)) {
                    SignFact("SUN IN", sky.sunSign); SignFact("MOON IN", sky.moonSign)
                }
            }
        }
        Box(Modifier.at(Rect(1000f, 56f, 1848f, 96f)), contentAlignment = Alignment.TopEnd) {
            Row(Modifier.height(40.dp).background(Color.Black.copy(alpha = 0.92f), RoundedCornerShape(50)).padding(horizontal = 20.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                for (layer in SkyLayer.entries) {
                    val on = layer in view.layers
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        Box(Modifier.size(8.dp).then(if (on) Modifier.background(HudTheme.accent, RoundedCornerShape(50))
                            else Modifier.border(1.5.dp, HudTheme.inkFaint, RoundedCornerShape(50))))
                        BasicText(layer.title, style = HudTheme.mont(13f, tracking = 2.5f, color = if (on) HudTheme.inkDim else HudTheme.inkFaint))
                    }
                }
            }
        }
        selected?.let { t ->
            Box(Modifier.at(Rect(72f, 760f, 1172f, 1040f)), contentAlignment = Alignment.BottomStart) {
                Column(Modifier.background(Color.Black.copy(alpha = 0.93f), RoundedCornerShape(26.dp)).border(1.5.dp, HudTheme.edge, RoundedCornerShape(26.dp))
                    .padding(horizontal = 30.dp, vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    BasicText(if (t.isUp) t.kind.title else t.kind.title + " · BELOW THE HORIZON", style = HudTheme.mont(15f, tracking = 3f, color = HudTheme.accent))
                    BasicText(t.name, style = HudTheme.mont(52f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (t.detail.isNotEmpty()) BasicText(t.detail, style = HudTheme.mont(22f, FontWeight.SemiBold, color = HudTheme.inkDim))
                    Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(34.dp)) {
                        for (f in t.facts) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            BasicText(f.label, style = HudTheme.mont(12f, tracking = 2.5f, color = HudTheme.inkFaint))
                            BasicText(f.value, style = HudTheme.mont(22f))
                        }
                    }
                }
            }
        }
        Box(Modifier.at(Rect(1200f, 1000f, 1848f, 1040f)), contentAlignment = Alignment.BottomEnd) {
            val parts = buildList {
                if (SkyLayer.planes in view.layers && overhead.status.isNotEmpty()) add(overhead.status)
                if (SkyLayer.planes in view.layers) add("AIRCRAFT · ADSB.LOL")
                if (SkyLayer.iss in view.layers && overhead.station != null) add("ISS · WHERETHEISS.AT")
            }
            BasicText(parts.joinToString("    "), style = HudTheme.mont(11f, tracking = 2.5f, color = HudTheme.inkFaint))
        }
    }
}

/** The compass word and degrees: the one piece of text that follows the heading, recomposed on its own. */
@Composable
private fun SkyBearing(facing: () -> Double) {
    val degrees = facing().roundToInt() % 360
    BasicText(SkyModel.compass(degrees.toDouble()), style = HudTheme.mont(64f))
    BasicText("$degrees°", style = HudTheme.mont(30f, color = HudTheme.inkDim), modifier = Modifier.padding(bottom = 8.dp))
}

@Composable
private fun SignFact(label: String, sign: Zodiac) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        val c = HudTheme.accent.copy(alpha = 0.9f)
        BasicText(label, style = HudTheme.mont(17f, tracking = 2.5f, color = c))
        BasicText(sign.glyph, style = TextStyle(fontSize = 24.sp, color = c))
        BasicText(sign.title, style = HudTheme.mont(17f, tracking = 2.5f, color = c))
    }
}

@Composable
fun SkyCanvas(sky: HudSnapshot.Sky, overhead: HudSnapshot.Overhead, layers: Set<SkyLayer>, projection: () -> SkyProjection, fov: Double, selected: SkyTarget?) {
    val text = rememberTextMeasurer(cacheSize = 256)
    val plane = rememberVectorPainter(Icons.Rounded.Flight)
    val night = sky.sunAltitude < -6
    val light = if (night) 1f else if (sky.sunAltitude < 0) 0.6f else 0.35f
    val zoom = sqrt(110 / fov).coerceIn(0.8, 1.9).toFloat()
    val radius = (projection().scale * 1.25 * PI / 180).toFloat()
    Box(Modifier.size(HudTheme.CANVAS_WIDTH.dp, HudTheme.CANVAS_HEIGHT.dp)) {
        if (SkyLayer.milkyWay in layers) {
            // Soft dots, blurred together into the band.
            Canvas(Modifier.fillMaxSize().blur((radius * 0.8f).dp)) {
                val pr = projection()
                val strength = floatArrayOf(0.07f, 0.1f, 0.13f, 0.17f, 0.22f)
                val tint = Color(0.8f, 0.86f, 1f)
                for (band in sky.milkyWay) {
                    val level = band.level.coerceIn(1, strength.size) - 1
                    val c = tint.copy(alpha = strength[level] * light)
                    for (point in band.points) {
                        val p = pr.project(point) ?: continue
                        if (pr.visible(p, radius * 2)) drawCircle(c, radius, p)
                    }
                }
            }
        }
        Canvas(Modifier.fillMaxSize()) {
            val pr = projection()
            if (SkyLayer.grid in layers) grid(pr, text)
            if (SkyLayer.zodiac in layers) ecliptic(sky, pr)
            if (SkyLayer.figures in layers) figures(sky, pr, light, SkyLayer.zodiac in layers)
            for (star in sky.stars) {
                val p = pr.project(star.az.toDouble(), star.alt.toDouble()) ?: continue
                if (!pr.visible(p, 10f)) continue
                val r = (4.6f - 0.8f * star.mag).coerceIn(0.8f, 6.5f) * zoom
                val colour = starColour(star.bv)
                if (star.mag < 1.8f) glow(p, r * 4.5f, colour, 0.28f * light)
                drawCircle(colour.copy(alpha = min(1f, 0.45f + light * 0.55f)), r, p)
            }
            if (SkyLayer.names in layers) names(sky, pr, light, SkyLayer.zodiac in layers, text)
            if (SkyLayer.zodiac in layers) signs(sky, pr, text)
            bodies(sky, pr, zoom, text)
            if (SkyLayer.iss in layers) overhead.station?.let { station(it, pr, text) }
            if (SkyLayer.planes in layers) for (f in overhead.planes.reversed()) {
                val p = pr.project(f.position) ?: continue
                if (!pr.visible(p)) continue
                val near = (1.4 - f.distance / 80).coerceIn(0.7, 1.4).toFloat()
                drawPath(line(f.trail.map { pr.project(it) } + p), Color.White.copy(alpha = 0.22f), style = Stroke(1.5f, cap = StrokeCap.Round))
                var angle = 0f
                pr.project(f.ahead)?.let { a -> if (hypot(a.x - p.x, a.y - p.y) > 0.5f) angle = atan2(a.y - p.y, a.x - p.x) }
                val side = 26 * near
                translate(p.x, p.y) {
                    // The icon points up; the heading is measured from the right.
                    rotateRad(angle + (PI / 2).toFloat(), Offset.Zero) {
                        translate(-side / 2, -side / 2) {
                            with(plane) { draw(Size(side, side), colorFilter = ColorFilter.tint(Color.White)) }
                        }
                    }
                }
                label(text, f.callsign, Offset(p.x + side * 0.7f, p.y - 9), HudTheme.mont(15 * near, color = Color.White), anchorLeft = true)
                val height = if (f.altitude >= 1000) "%.1f KM".format(f.altitude / 1000) else "${f.altitude.toInt()} M"
                label(text, listOfNotNull(f.model, height).joinToString(" · "), Offset(p.x + side * 0.7f, p.y + 9),
                    HudTheme.mont(11 * near, tracking = 1.5f, color = Color.White.copy(alpha = 0.5f)), anchorLeft = true)
            }
            ground(pr, text)
            selected?.let { mark(pr, it) }
        }
    }
}

private fun line(points: List<Offset?>, jump: Float = 900f, closed: Boolean = false): Path {
    val path = Path()
    var last: Offset? = null
    for (p in points) {
        if (p == null) { last = null; continue }
        val l = last
        if (l != null && hypot(p.x - l.x, p.y - l.y) < jump) path.lineTo(p.x, p.y) else path.moveTo(p.x, p.y)
        last = p
    }
    if (closed) path.close()
    return path
}

private fun DrawScope.glow(p: Offset, r: Float, colour: Color, strength: Float) {
    drawCircle(Brush.radialGradient(listOf(colour.copy(alpha = strength), colour.copy(alpha = 0f)), center = p, radius = r), r, p)
}

/** Text centred on a point, or starting at it. */
private fun DrawScope.label(text: TextMeasurer, s: String, at: Offset, style: TextStyle, anchorLeft: Boolean = false, bottomLeft: Boolean = false) {
    val m = text.measure(s, style)
    val x = if (anchorLeft || bottomLeft) at.x else at.x - m.size.width / 2
    val y = if (bottomLeft) at.y - m.size.height else at.y - m.size.height / 2
    drawText(m, topLeft = Offset(x, y))
}

private fun DrawScope.grid(pr: SkyProjection, text: TextMeasurer) {
    val style = Stroke(1f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3f, 7f)))
    for (altitude in listOf(15.0, 30.0, 45.0, 60.0, 75.0)) {
        drawPath(line((0..120).map { pr.project(it * 3.0, altitude) }), Color.White.copy(alpha = 0.09f), style = style)
        pr.project(pr.facing + 4, altitude)?.takeIf { pr.visible(it) }?.let {
            label(text, "${altitude.toInt()}°", it, HudTheme.mont(12f, color = Color.White.copy(alpha = 0.25f)), bottomLeft = true)
        }
    }
    for (az in 0 until 360 step 30) drawPath(line((0..20).map { pr.project(az.toDouble(), it * 4.0) }), Color.White.copy(alpha = 0.06f), style = style)
}

private fun DrawScope.ecliptic(sky: HudSnapshot.Sky, pr: SkyProjection) {
    val points = sky.ecliptic.map { pr.project(it) }
    drawPath(line(points), HudTheme.accent.copy(alpha = 0.5f), style = Stroke(1.6f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 9f))))
    for (i in 0 until sky.ecliptic.size - 1 step 15) {
        val p = points[i] ?: continue
        val q = points[i + 1] ?: continue
        if (!pr.visible(p)) continue
        val a = atan2(q.y - p.y, q.x - p.x) + (PI / 2).toFloat()
        drawLine(HudTheme.accent.copy(alpha = 0.7f), Offset(p.x - cos(a) * 11, p.y - sin(a) * 11), Offset(p.x + cos(a) * 11, p.y + sin(a) * 11), 2f)
    }
}

private fun DrawScope.signs(sky: HudSnapshot.Sky, pr: SkyProjection, text: TextMeasurer) {
    for (s in sky.signs) {
        if (s.alt <= -3) continue
        val p = pr.project(s.az.toDouble(), s.alt.toDouble()) ?: continue
        if (!pr.visible(p)) continue
        val now = s.sign == sky.sunSign
        if (now) glow(p, 46f, HudTheme.accent, 0.3f)
        label(text, s.sign.glyph, p, TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Light, color = HudTheme.accent.copy(alpha = if (now) 1f else 0.85f)))
        label(text, s.sign.title, Offset(p.x, p.y + 48), HudTheme.mont(12f, tracking = 3f, color = HudTheme.accent.copy(alpha = 0.7f)))
    }
}

private fun DrawScope.figures(sky: HudSnapshot.Sky, pr: SkyProjection, light: Float, zodiac: Boolean) {
    for (f in sky.lines) {
        val path = line(f.points.map { pr.project(it) }, 400f)
        if (zodiac && f.zodiac) drawPath(path, HudTheme.accent.copy(alpha = 0.45f * light), style = Stroke(1.6f))
        else drawPath(path, Color.White.copy(alpha = 0.2f * light), style = Stroke(1.2f))
    }
}

private fun DrawScope.names(sky: HudSnapshot.Sky, pr: SkyProjection, light: Float, zodiac: Boolean, text: TextMeasurer) {
    for (l in sky.constellations) {
        val p = pr.project(l.az.toDouble(), l.alt.toDouble()) ?: continue
        if (!pr.visible(p)) continue
        val gold = zodiac && l.zodiac
        label(text, l.name, p, HudTheme.mont(13f, tracking = 3.5f, color = (if (gold) HudTheme.accent else Color.White).copy(alpha = (if (gold) 0.6f else 0.3f) * light)))
    }
    for (l in sky.starNames) {
        val p = pr.project(l.az.toDouble(), l.alt.toDouble()) ?: continue
        if (!pr.visible(p)) continue
        label(text, l.name, Offset(p.x + 12, p.y - 12), HudTheme.mont(15f, FontWeight.SemiBold, color = Color.White.copy(alpha = 0.62f * light)), anchorLeft = true)
    }
}

private fun DrawScope.bodies(sky: HudSnapshot.Sky, pr: SkyProjection, zoom: Float, text: TextMeasurer) {
    for (b in sky.bodies) {
        val p = pr.project(b.az, b.alt) ?: continue
        if (!pr.visible(p, 80f)) continue
        when (b.kind) {
            HudSnapshot.Sky.Body.Kind.sun -> {
                glow(p, 90 * zoom, HudTheme.accent, 0.4f)
                drawCircle(HudTheme.accent, 20 * zoom, p)
                label(text, "SUN", Offset(p.x + 30 * zoom, p.y), HudTheme.mont(16f, tracking = 3f, color = HudTheme.accent), anchorLeft = true)
            }
            HudSnapshot.Sky.Body.Kind.moon -> {
                glow(p, 70 * zoom, Color.White, 0.16f)
                val side = 44 * zoom
                moon(sky.moonPhaseIndex, p, side / 2, Color.White)
                label(text, "MOON", Offset(p.x + side / 2 + 10, p.y), HudTheme.mont(16f, tracking = 3f, color = Color.White.copy(alpha = 0.85f)), anchorLeft = true)
            }
            HudSnapshot.Sky.Body.Kind.planet -> {
                val c = planetColour(b.name)
                val r = (5 - 0.7 * b.mag).coerceIn(4.0, 8.0).toFloat() * zoom
                glow(p, r * 4, c, 0.35f)
                drawCircle(c, r, p)
                if (b.name == "SATURN") drawOval(c.copy(alpha = 0.8f), Offset(p.x - r * 2.1f, p.y - r * 0.7f), Size(r * 4.2f, r * 1.4f), style = Stroke(1.4f))
                label(text, b.name, Offset(p.x + r + 10, p.y), HudTheme.mont(16f, tracking = 3f, color = c), anchorLeft = true)
            }
        }
    }
}

private fun DrawScope.station(s: HudSnapshot.Overhead.Station, pr: SkyProjection, text: TextMeasurer) {
    drawPath(line(s.path.map { pr.project(it) }), stationColour.copy(alpha = 0.55f),
        style = Stroke(2f, cap = StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2f, 10f))))
    val p = pr.project(s.position) ?: return
    if (!pr.visible(p)) return
    glow(p, 34f, stationColour, if (s.sunlit) 0.45f else 0.15f)
    drawRect(stationColour, Offset(p.x - 4, p.y - 4), Size(8f, 8f))
    drawRect(stationColour, Offset(p.x - 20, p.y - 6), Size(11f, 12f), style = Stroke(1.6f))
    drawRect(stationColour, Offset(p.x + 9, p.y - 6), Size(11f, 12f), style = Stroke(1.6f))
    label(text, "ISS", Offset(p.x + 30, p.y - 9), HudTheme.mont(18f, tracking = 3f, color = stationColour), anchorLeft = true)
    label(text, "${s.altitude.roundToInt()} KM UP", Offset(p.x + 30, p.y + 11), HudTheme.mont(12f, tracking = 2f, color = stationColour.copy(alpha = 0.7f)), anchorLeft = true)
}

private fun DrawScope.ground(pr: SkyProjection, text: TextMeasurer) {
    val h = pr.horizon() ?: return
    val c = h.centre; val r = h.radius
    val circle = Path().apply { addOval(Rect(c.x - r, c.y - r, c.x + r, c.y + r)) }
    if (h.groundInside) {
        drawPath(circle, Color.Black)
        drawPath(circle, Brush.radialGradient(0f to Color.Transparent, (max(r - 170, 0f) / r) to Color.Transparent,
            1f to Color.White.copy(alpha = 0.08f), center = c, radius = r))
    } else {
        val earth = Path().apply {
            fillType = PathFillType.EvenOdd
            addRect(Rect(-2000f, -2000f, size.width + 2000, size.height + 2000)); addOval(Rect(c.x - r, c.y - r, c.x + r, c.y + r))
        }
        drawPath(earth, Color.Black)
        drawPath(earth, Brush.radialGradient(0f to Color.White.copy(alpha = 0.08f), (r / (r + 170)) to Color.White.copy(alpha = 0.08f),
            1f to Color.Transparent, center = c, radius = r + 170))
    }
    drawPath(circle, Color.White.copy(alpha = 0.4f), style = Stroke(1.6f))
    for (az in 0 until 360 step 5) {
        val p = pr.project(az.toDouble(), 0.0) ?: continue
        if (!pr.visible(p)) continue
        val major = az % 45 == 0; val mid = az % 15 == 0
        var ox = p.x - c.x; var oy = p.y - c.y
        val len = max(hypot(ox, oy), 0.001f)
        ox /= len; oy /= len
        if (h.groundInside) { ox = -ox; oy = -oy }
        val reach = if (major) 18f else if (mid) 11f else 6f
        drawLine(Color.White.copy(alpha = if (major) 0.7f else 0.35f), p, Offset(p.x + ox * reach, p.y + oy * reach), if (major) 2f else 1.2f)
        if (major) {
            val name = SkyModel.compass(az.toDouble())
            label(text, name, Offset(p.x + ox * 42, p.y + oy * 42), HudTheme.mont(if (name.length == 1) 30f else 20f,
                color = if (name == "N") HudTheme.accent else Color.White.copy(alpha = 0.8f)))
        } else if (mid) {
            label(text, "$az", Offset(p.x + ox * 26, p.y + oy * 26), HudTheme.mont(12f, color = Color.White.copy(alpha = 0.35f)))
        }
    }
}

private fun DrawScope.mark(pr: SkyProjection, t: SkyTarget) {
    val p = pr.project(t.az, t.alt) ?: return
    if (pr.visible(p, -30f)) {
        val r = 34f; val arm = 12f
        val b = Path()
        for ((sx, sy) in listOf(-1f to -1f, 1f to -1f, 1f to 1f, -1f to 1f)) {
            val cx = p.x + r * sx; val cy = p.y + r * sy
            b.moveTo(cx, cy - arm * sy); b.lineTo(cx, cy); b.lineTo(cx - arm * sx, cy)
        }
        drawPath(b, HudTheme.accent, style = Stroke(3f))
    } else {
        val c = Offset(size.width / 2, size.height / 2)
        val a = atan2(p.y - c.y, p.x - c.x)
        val e = Offset((c.x + cos(a) * 2000).coerceIn(70f, size.width - 70), (c.y + sin(a) * 2000).coerceIn(120f, size.height - 120))
        translate(e.x, e.y) {
            rotateRad(a, Offset.Zero) {
                drawPath(Path().apply { moveTo(-14f, -20f); lineTo(10f, 0f); lineTo(-14f, 20f) }, HudTheme.accent,
                    style = Stroke(5f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
    }
}
