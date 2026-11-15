package com.thehud.glasses

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.WbTwilight
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import com.thehud.core.MusicLayout
import java.text.NumberFormat
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// The widgets that are new to Android, each drawn for one slot, as HudWidgets.swift draws them.

fun Int.grouped(): String = NumberFormat.getIntegerInstance().format(this)

// ------------------------------------------------------------------ map

@Composable
fun MapWidget(minimap: HudSnapshot.Minimap, ground: ImageBitmap?, standIn: Boolean, heading: () -> Double = { minimap.heading }) {
    Box(Modifier.fillMaxSize()) {
        MinimapPanel(minimap, ground, standIn, showsHeader = false, heading = heading)
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart = HudTheme.CORNER.dp, topEnd = HudTheme.CORNER.dp))
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.85f), Color.Transparent)))
            .padding(start = 22.dp, end = 22.dp, top = 16.dp, bottom = 30.dp), verticalAlignment = Alignment.CenterVertically) {
            BasicText(minimap.place, style = HudTheme.mont(17f, tracking = 2.5f), maxLines = 1, modifier = Modifier.weight(1f))
            BasicText(minimap.speed, style = HudTheme.mont(16f, tracking = 2f, color = HudTheme.inkDim))
        }
    }
}

/**
 * The moving map: the raster turned to the heading and slid under the marker, the route over
 * it, the cone, the scale and the north needle on top.
 */
@Composable
fun MinimapPanel(minimap: HudSnapshot.Minimap, ground: ImageBitmap?, standIn: Boolean, showsHeader: Boolean = true,
                 /** Read only while drawing, so turning redraws the map without recomposing it. */
                 heading: () -> Double = { minimap.heading }) {
    val shape = RoundedCornerShape(HudTheme.CORNER.dp)
    val text = rememberTextMeasurer()
    BoxWithConstraints(Modifier.fillMaxSize().clip(shape).background(Color.Black).border(1.dp, HudTheme.edge, shape)) {
        val ppm = minimap.pointsPerMetre.toFloat()
        if (ground != null) {
            val side = (minimap.effectiveGroundSpan * ppm).toFloat()
            Box(Modifier.fillMaxSize().graphicsLayer { rotationZ = -heading().toFloat() }, contentAlignment = Alignment.Center) {
                Box(Modifier.requiredSize(side.dp).offset((-minimap.groundOffsetEast * ppm).toFloat().dp, (minimap.groundOffsetNorth * ppm).toFloat().dp)) {
                    Image(ground, null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
                    Canvas(Modifier.fillMaxSize()) { route(minimap, ppm) }
                }
            }
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)))
        } else if (standIn) {
            Canvas(Modifier.fillMaxSize()) { streets(heading()) }
        } else {
            Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.04f)))
        }
        // The edge fades to black, so the map has no hard border on the glasses.
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(
            0.6f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.75f),
            radius = max(constraints.maxWidth, constraints.maxHeight) * 0.75f)))
        Canvas(Modifier.fillMaxSize()) {
            val c = Offset(size.width / 2, size.height / 2)
            val cone = Path().apply { moveTo(c.x, c.y); lineTo(c.x - 30, c.y - 66); lineTo(c.x + 30, c.y - 66); close() }
            drawPath(cone, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.42f), Color.Transparent), startY = c.y, endY = c.y - 66))
            drawCircle(Color.White, 11f, c)
            drawCircle(HudTheme.accent, 17f, c, style = Stroke(3f))

            val barY = size.height - 30
            val (metres, label) = scaleBar(minimap.pointsPerMetre)
            val length = (metres * minimap.pointsPerMetre).toFloat()
            val barX = if (showsHeader) 24f else size.width - 104 - length
            val ink = Color.White.copy(alpha = 0.65f)
            drawLine(ink, Offset(barX, barY), Offset(barX + length, barY), 3f)
            for (x in listOf(barX, barX + length)) drawLine(ink, Offset(x, barY - 6), Offset(x, barY + 6), 3f)
            val measured = text.measure(label, HudTheme.mont(15f, color = HudTheme.inkDim))
            drawText(measured, topLeft = Offset(barX + length / 2 - measured.size.width / 2, barY - 20 - measured.size.height / 2))

            val n = Offset(size.width - 48, size.height - 48)
            drawCircle(Color.White.copy(alpha = 0.22f), 24f, n, style = Stroke(2f))
            val facing = heading()
            rotate(-facing.toFloat(), n) {
                drawPath(Path().apply { moveTo(n.x, n.y - 19); lineTo(n.x - 7, n.y + 3); lineTo(n.x + 7, n.y + 3); close() },
                    Color.White.copy(alpha = 0.85f))
            }
            val h = text.measure(com.thehud.core.SkyModel.compass(facing), HudTheme.mont(14f, color = HudTheme.inkDim))
            drawText(h, topLeft = Offset(n.x - h.size.width / 2, n.y + 34 - h.size.height / 2))
        }
    }
}

fun scaleBar(pointsPerMetre: Double): Pair<Int, String> {
    val steps = listOf(10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000)
    val metres = steps.firstOrNull { it * pointsPerMetre >= 80 } ?: steps.last()
    return metres to if (metres >= 1000) "${metres / 1000} KM" else "$metres M"
}

private fun DrawScope.route(minimap: HudSnapshot.Minimap, ppm: Float) {
    if (minimap.route.size < 2) return
    fun p(o: Offset) = Offset(size.width / 2 + o.x * ppm, size.height / 2 - o.y * ppm)
    val line = Path().apply { moveTo(p(minimap.route[0]).x, p(minimap.route[0]).y); minimap.route.drop(1).forEach { lineTo(p(it).x, p(it).y) } }
    drawPath(line, Color.Black.copy(alpha = 0.7f), style = Stroke(18f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(line, HudTheme.accent, style = Stroke(10f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    val end = p(minimap.route.last())
    drawCircle(Color.Black.copy(alpha = 0.7f), 16f, end)
    drawCircle(HudTheme.accent, 11f, end)
    drawCircle(Color.Black, 4f, end)
}

/** Made-up streets, for stills only: a made-up map on someone's face is worse than none. */
private fun DrawScope.streets(heading: Double) {
    drawRect(Color.White.copy(alpha = 0.04f))
    fun seeded(n: Int): Float { val x = sin(n * 12.9898) * 43758.5453; return (x - floor(x)).toFloat() }
    val diagonal = max(size.width, size.height) * 1.6f
    translate(size.width / 2, size.height / 2) {
        rotate(-heading.toFloat(), Offset.Zero) {
            for (i in 0 until 14) {
                val bx = (seeded(i * 3) - 0.5f) * diagonal * 0.8f; val by = (seeded(i * 3 + 1) - 0.5f) * diagonal * 0.8f
                drawRect(Color.White.copy(alpha = 0.05f), Offset(bx, by), Size(40 + seeded(i * 3 + 2) * 90, 40 + seeded(i * 7) * 90))
            }
            for (i in -8..8) {
                val j = (seeded(i + 100) - 0.5f) * 18; val j2 = (seeded(i + 200) - 0.5f) * 18
                val w = if (i % 3 == 0) 5f else 2.5f
                val a = if (i % 3 == 0) 0.26f else 0.14f
                drawLine(Color.White.copy(alpha = a), Offset(i * 86 + j, -diagonal / 2), Offset(i * 86 - j, diagonal / 2), w)
                drawLine(Color.White.copy(alpha = a), Offset(-diagonal / 2, i * 86 + j2), Offset(diagonal / 2, i * 86 - j2), w)
            }
        }
        val route = Path().apply {
            moveTo(-260f, 300f); cubicTo(-200f, 190f, -120f, 120f, -40f, 40f); cubicTo(40f, -40f, 150f, -120f, 250f, -230f)
        }
        drawPath(route, HudTheme.accent, style = Stroke(9f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

// ------------------------------------------------------------------ activity

@Composable
fun ProgressRing(fraction: Double, lineWidth: Float, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val inset = lineWidth / 2
        val s = Size(size.width - lineWidth, size.height - lineWidth)
        drawArc(Color.White.copy(alpha = 0.1f), 0f, 360f, false, Offset(inset, inset), s, style = Stroke(lineWidth))
        drawArc(HudTheme.accent, -90f, (max(fraction, 0.001) * 360).toFloat(), false, Offset(inset, inset), s,
            style = Stroke(lineWidth, cap = StrokeCap.Round))
    }
}

@Composable
fun ActivityWidget(activity: HudSnapshot.Activity?) {
    if (activity == null) {
        Column(Modifier.surface(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Label("ACTIVITY")
            BasicText("Counting steps needs Physical activity access", style = HudTheme.mont(22f, FontWeight.SemiBold, color = HudTheme.inkDim))
        }
        return
    }
    Row(Modifier.surface(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(26.dp)) {
        Box(Modifier.size(160.dp), contentAlignment = Alignment.Center) {
            ProgressRing(activity.fraction, 18f, Modifier.fillMaxSize())
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                HudIcon(Icons.Rounded.DirectionsWalk, 36f)
                BasicText("${(activity.fraction * 100).toInt()}%", style = HudTheme.mont(22f))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Label("STEPS")
            BasicText(activity.steps.grouped(), style = HudTheme.mont(48f, tracking = -1f), maxLines = 1)
            activity.distanceKm?.let { Stat("%.1f".format(it), "KM") }
            activity.floors?.let { Stat("$it", if (it == 1) "FLOOR" else "FLOORS") }
        }
    }
}

@Composable
private fun Stat(value: String, unit: String) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        BasicText(value, style = HudTheme.mont(26f))
        BasicText(unit, style = HudTheme.mont(15f, tracking = 2f, color = HudTheme.inkDim), modifier = Modifier.padding(bottom = 3.dp))
    }
}

// ------------------------------------------------------------------ sky

@Composable
fun SkyWidget(sky: HudSnapshot.Sky) {
    Column(Modifier.surface()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Label(if (sky.dayProgress == null) "TONIGHT" else "TODAY")
            Spacer(Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                MoonGlyph(sky.moonPhaseIndex, Modifier.size(40.dp))
                BasicText("${sky.moonIllumination}%", style = HudTheme.mont(16f, color = HudTheme.inkDim))
            }
        }
        DayArc(sky.dayProgress, sky.sunAltitude, Modifier.fillMaxWidth().height(104.dp).offset(y = (-24).dp))
        Row(Modifier.fillMaxWidth().offset(y = (-14).dp), horizontalArrangement = Arrangement.SpaceBetween) {
            SkyTime(Icons.Rounded.ArrowUpward, sky.sunrise)
            SkyTime(Icons.Rounded.WbTwilight, sky.goldenHour, accent = true)
            SkyTime(Icons.Rounded.ArrowDownward, sky.sunset)
        }
        Spacer(Modifier.weight(1f))
        BasicText(if (sky.hasLocation) sky.moonPhase else "WAITING FOR A LOCATION",
            style = HudTheme.mont(16f, tracking = 2.5f, color = HudTheme.inkDim), maxLines = 1)
    }
}

@Composable
private fun SkyTime(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String?, accent: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        HudIcon(icon, 16f, if (accent) HudTheme.accent else HudTheme.inkDim)
        BasicText(text ?: "--", style = HudTheme.mont(20f), maxLines = 1)
    }
}

/** The moon as it looks tonight: the lit part of a disc, from the phase's eighth. */
@Composable
fun MoonGlyph(phase: Int, modifier: Modifier, color: Color = HudTheme.ink) {
    Canvas(modifier) { moon(phase, Offset(size.width / 2, size.height / 2), min(size.width, size.height) / 2 - 1.5f, color) }
}

/** The lit part of the moon, terminator and all: waxing lit on the right, as seen from the north. */
fun DrawScope.moon(phase: Int, c: Offset, r: Float, color: Color) {
    drawCircle(color.copy(alpha = 0.16f), r, c)
    drawCircle(color.copy(alpha = 0.5f), r, c, style = Stroke(1.5f))
    if (phase == 0) return
    val a = phase / 8.0 * 2 * PI
    val k = cos(a).toFloat()
    val s = if (a <= PI) 1f else -1f
    val path = Path()
    val steps = 32
    for (i in 0..steps) {
        val t = -PI / 2 + PI * i / steps
        val x = c.x + s * r * cos(t).toFloat(); val y = c.y + r * sin(t).toFloat()
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    for (i in steps downTo 0) {
        val t = -PI / 2 + PI * i / steps
        path.lineTo(c.x + s * r * k * cos(t).toFloat(), c.y + r * sin(t).toFloat())
    }
    path.close()
    drawPath(path, color)
}

/** The sun's path from sunrise to sunset as an arc over the horizon, with the sun on it. */
@Composable
fun DayArc(progress: Double?, sunAltitude: Double, modifier: Modifier) {
    Canvas(modifier) {
        val horizon = size.height - 8
        val left = Offset(8f, horizon); val right = Offset(size.width - 8, horizon)
        val peak = Offset(size.width / 2, horizon - (size.height - 20) * 2)
        fun point(t: Float): Offset {
            val a = (1 - t) * (1 - t); val b = 2 * (1 - t) * t; val c = t * t
            return Offset(a * left.x + b * peak.x + c * right.x, a * left.y + b * peak.y + c * right.y)
        }
        val arc = Path().apply { moveTo(left.x, left.y); quadraticTo(peak.x, peak.y, right.x, right.y) }
        drawPath(arc, Color.White.copy(alpha = 0.25f), style = Stroke(2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 6f))))
        drawLine(Color.White.copy(alpha = 0.35f), Offset(0f, horizon), Offset(size.width, horizon), 1.5f)
        if (progress != null) {
            val done = Path().apply { moveTo(left.x, left.y); for (s in 1..40) point((progress * s / 40).toFloat()).let { lineTo(it.x, it.y) } }
            drawPath(done, HudTheme.accent.copy(alpha = 0.8f), style = Stroke(3f))
            drawCircle(HudTheme.accent, 13f, point(progress.toFloat()))
        } else {
            val depth = (min(max(-sunAltitude, 0.0), 18.0) / 18).toFloat()
            drawCircle(HudTheme.accent.copy(alpha = 0.5f), 9f, Offset(size.width / 2, horizon + 4 + depth * 6), style = Stroke(2f))
        }
    }
}

// ------------------------------------------------------------------ music

@Composable
fun MusicButton(control: MusicLayout.Control, isPlaying: Boolean, large: Boolean, hovered: Boolean, modifier: Modifier) {
    val shape = RoundedCornerShape(if (large) 30.dp else 16.dp)
    val play = control == MusicLayout.Control.playPause
    Box(modifier.clip(shape).background(if (play) HudTheme.accent else Color.White.copy(alpha = if (hovered) 0.2f else 0.08f))
        .border(2.dp, if (hovered) Color.White.copy(alpha = 0.7f) else Color.Transparent, shape), contentAlignment = Alignment.Center) {
        HudIcon(when (control) {
            MusicLayout.Control.previous -> Icons.Rounded.SkipPrevious
            MusicLayout.Control.next -> Icons.Rounded.SkipNext
            MusicLayout.Control.playPause -> if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow
        }, if (large) 64f else 32f, if (play) Color.Black else HudTheme.ink)
    }
}

@Composable
fun Artwork(image: ImageBitmap?, corner: Float, modifier: Modifier) {
    Box(modifier.clip(RoundedCornerShape(corner.dp)).background(Color.White.copy(alpha = 0.07f)), contentAlignment = Alignment.Center) {
        if (image != null) Image(image, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else HudIcon(Icons.Rounded.MusicNote, 48f, HudTheme.inkDim)
    }
}

@Composable
fun ProgressLine(progress: Float, modifier: Modifier) {
    Box(modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.14f))) {
        Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).fillMaxHeight().background(HudTheme.ink, RoundedCornerShape(50)))
    }
}

@Composable
fun MusicWidget(music: HudSnapshot.NowPlaying?, artwork: ImageBitmap?, hover: Offset?, size: Size) {
    Box(Modifier.surface(0f)) {
        Row(Modifier.padding(26.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            Artwork(artwork, 14f, Modifier.size(112.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Label(if (music?.isPlaying == true) "NOW PLAYING" else "MUSIC", accent = music?.isPlaying == true)
                BasicText(music?.title ?: "Nothing playing", style = HudTheme.mont(24f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                BasicText(music?.artist?.ifEmpty { music.app } ?: "Play something on the phone",
                    style = HudTheme.mont(18f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (music != null) {
            ProgressLine(music.progress, Modifier.offset(26.dp, (size.height - 26 - 56 - 22).dp).size((size.width - 52).dp, 4.dp))
        }
        for ((control, frame) in MusicLayout.buttons(size, large = false)) {
            MusicButton(control, music?.isPlaying ?: false, false, hover?.let { frame.contains(it) } ?: false, Modifier.at(frame))
        }
    }
}

// ------------------------------------------------------------------ captions

@Composable
fun CaptionsWidget(captions: HudSnapshot.Captions) {
    Column(Modifier.surface()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Label("CAPTIONS")
            Spacer(Modifier.weight(1f))
            if (captions.isListening) BasicText(captions.elapsed, style = HudTheme.mont(16f, color = HudTheme.inkDim))
            BasicText(captions.status, style = HudTheme.mont(14f, tracking = 2f, color = if (captions.isListening) HudTheme.accent else HudTheme.inkFaint),
                maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.weight(1f))
        if (captions.isListening || captions.lines.isNotEmpty()) CaptionLines(captions, 23f, 5)
        else {
            BasicText("Click to start listening", style = HudTheme.mont(24f, FontWeight.SemiBold, color = HudTheme.inkFaint))
            Spacer(Modifier.weight(1f))
        }
    }
}

/** The last few lines of a transcript, newest at the bottom and brightest. */
@Composable
fun CaptionLines(captions: HudSnapshot.Captions, size: Float, count: Int, modifier: Modifier = Modifier) {
    val lines = captions.lines.takeLast(if (captions.partial.isEmpty()) count else count - 1)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy((size * 0.3f).dp)) {
        lines.forEachIndexed { i, line ->
            val age = lines.size - i
            BasicText(line, style = HudTheme.mont(size, FontWeight.SemiBold, color = Color.White.copy(alpha = max(0.95f - age * 0.15f, 0.35f))),
                maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        if (captions.partial.isNotEmpty()) BasicText(captions.partial, style = HudTheme.mont(size, FontWeight.SemiBold, color = HudTheme.accent),
            maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

/** Frames as the canvas gives them, for the widget's own points. */
fun Rect.local(origin: Offset) = translate(-origin.x, -origin.y)
