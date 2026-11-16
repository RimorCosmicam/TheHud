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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DesktopMac
import androidx.compose.material.icons.rounded.DirectionsCar
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Place
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material.icons.rounded.TurnLeft
import androidx.compose.material.icons.rounded.TurnRight
import androidx.compose.material.icons.rounded.TurnSlightLeft
import androidx.compose.material.icons.rounded.TurnSlightRight
import androidx.compose.material.icons.rounded.UTurnLeft
import androidx.compose.material.icons.rounded.RoundaboutRight
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.thehud.core.BrowserMetrics
import com.thehud.core.ClockAppLayout
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import com.thehud.core.MapsLayout
import com.thehud.core.MusicLayout
import kotlin.math.max

// The widgets held up alone, as the iPhone app's *App views draw them, at the safe frame's
// 1792 by 952 points. And the Mac, the big panel that shows something else.

private val appSize = Size(1792f, 952f)

@Composable
private fun AppSurface(content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(HudTheme.CORNER.dp)
    Box(Modifier.fillMaxSize().clip(shape).background(HudTheme.surface).border(1.dp, HudTheme.edge, shape)) { content() }
}

@Composable
private fun Divider(vertical: Boolean = false) {
    Box(if (vertical) Modifier.width(1.dp).height(40.dp).background(Color.White.copy(alpha = 0.12f))
        else Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.1f)))
}

// ------------------------------------------------------------------ clock

@Composable
fun ClockApp(clock: HudSnapshot.Clock, timer: HudSnapshot.TimerReading, hover: Offset?) = AppSurface {
    Box(Modifier.at(Rect(72f, 56f, 400f, 80f))) { Label("CLOCK") }
    ClockDial(clock, Modifier.at(Rect(Offset(60f, 126f), Size(700f, 700f))))
    Column(Modifier.at(Rect(Offset(824f, 40f), Size(916f, 270f))), verticalArrangement = Arrangement.Bottom) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            BasicText(clock.time, style = HudTheme.mont(176f, tracking = -6f), maxLines = 1)
            Column(Modifier.padding(bottom = 34.dp)) {
                clock.meridiem?.let { BasicText(it, style = HudTheme.mont(34f)) }
                BasicText(clock.seconds, style = HudTheme.mont(64f, color = HudTheme.accent))
            }
        }
        BasicText("${clock.weekday}  ·  ${clock.date}", style = HudTheme.mont(28f, tracking = 4f, color = HudTheme.inkDim), maxLines = 1)
    }
    TimerCard(timer, hover?.let { ClockAppLayout.timerCard.contains(it) } ?: false, Modifier.at(ClockAppLayout.timerCard))
    Column(Modifier.at(Rect(Offset(1300f, 340f), Size(440f, 310f))), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Label("TODAY")
        val events = clock.agenda.take(3)
        if (events.isEmpty()) BasicText("Nothing else today", style = HudTheme.mont(26f, FontWeight.SemiBold, color = HudTheme.inkFaint))
        for (e in events) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(5.dp, 46.dp).background(if (e.isNow) HudTheme.accent else Color.White.copy(alpha = 0.3f), RoundedCornerShape(2.dp)))
            Column {
                BasicText(e.title, style = HudTheme.mont(28f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                BasicText(if (e.isNow) "NOW · UNTIL ${e.end ?: ""}" else e.end?.let { "${e.time} – $it" } ?: e.time,
                    style = HudTheme.mont(18f, tracking = 2f, color = if (e.isNow) HudTheme.accent else HudTheme.inkDim))
            }
        }
    }
    Row(Modifier.at(Rect(Offset(824f, 730f), Size(916f, 170f))), verticalAlignment = Alignment.CenterVertically) {
        clock.worldClocks.forEachIndexed { i, w ->
            if (i > 0) Box(Modifier.width(1.dp).height(110.dp).background(Color.White.copy(alpha = 0.1f)))
            Column(Modifier.weight(1f).padding(horizontal = 28.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HudIcon(if (w.isDay) Icons.Rounded.WbSunny else Icons.Rounded.NightsStay, 16f, HudTheme.inkDim)
                    BasicText(w.city, style = HudTheme.mont(16f, tracking = 3f, color = HudTheme.inkDim))
                }
                BasicText(w.time, style = HudTheme.mont(40f))
                BasicText(w.offset, style = HudTheme.mont(16f, tracking = 2f, color = HudTheme.inkFaint))
            }
        }
    }
}

@Composable
private fun TimerCard(timer: HudSnapshot.TimerReading, hovered: Boolean, modifier: Modifier) {
    val shape = RoundedCornerShape(26.dp)
    val idle = timer.state == HudSnapshot.TimerState.idle
    Column(modifier.clip(shape).background(Color.White.copy(alpha = if (hovered) 0.1f else 0.05f))
        .border(2.dp, if (hovered) HudTheme.accent.copy(alpha = 0.7f) else Color.Transparent, shape).padding(30.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BasicText(when { timer.state == HudSnapshot.TimerState.done -> "TIME'S UP"; timer.isStopwatch -> "STOPWATCH"; else -> "TIMER" },
                style = HudTheme.mont(18f, tracking = 3f, color = if (idle) HudTheme.inkDim else HudTheme.accent))
            Spacer(Modifier.weight(1f))
            HudIcon(if (timer.state == HudSnapshot.TimerState.running) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, 30f, HudTheme.inkDim)
        }
        BasicText(timer.text, style = HudTheme.mont(110f, tracking = -3f), maxLines = 1)
        ProgressLine(timer.progress ?: 0f, Modifier.fillMaxWidth().height(6.dp))
        BasicText(when (timer.state) {
            HudSnapshot.TimerState.idle -> "SCROLL TO SET · CLICK TO START"
            HudSnapshot.TimerState.running -> "CLICK TO PAUSE"
            HudSnapshot.TimerState.paused -> "CLICK TO GO ON · RIGHT-CLICK TO RESET"
            HudSnapshot.TimerState.done -> "CLICK TO RUN AGAIN"
        }, style = HudTheme.mont(14f, tracking = 2f, color = HudTheme.inkFaint), maxLines = 1)
    }
}

/** An analogue face: ticks, four numbers, three hands. */
@Composable
fun ClockDial(clock: HudSnapshot.Clock, modifier: Modifier) {
    Box(modifier) {
        Canvas(Modifier.fillMaxSize()) {
            val c = Offset(size.width / 2, size.height / 2)
            val r = size.minDimension / 2
            val outer = r - 22
            for (i in 0 until 60) {
                val hour = i % 5 == 0
                val len = if (hour) 40f else 14f
                rotate(i * 6f, c) {
                    drawLine(if (hour) HudTheme.ink else Color.White.copy(alpha = 0.35f), Offset(c.x, c.y - outer), Offset(c.x, c.y - outer + len),
                        if (hour) 7f else 2.5f, StrokeCap.Round)
                }
            }
            fun hand(turns: Double, length: Float, width: Float, color: Color, tail: Float = 0f) {
                rotate((turns * 360).toFloat(), c) {
                    drawLine(Color.Black.copy(alpha = 0.6f), Offset(c.x, c.y + tail), Offset(c.x, c.y - length), width + 6, StrokeCap.Round)
                    drawLine(color, Offset(c.x, c.y + tail), Offset(c.x, c.y - length), width, StrokeCap.Round)
                }
            }
            hand(clock.hourHand / 12, r * 0.52f, 16f, HudTheme.ink)
            hand(clock.minuteHand / 60, r * 0.76f, 10f, HudTheme.ink)
            hand(clock.secondHand / 60, r * 0.84f, 4f, HudTheme.accent, 56f)
            drawCircle(HudTheme.accent, 14f, c)
            drawCircle(Color.Black, 5f, c)
        }
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val r = maxWidth.value / 2
            for ((n, dx, dy) in listOf(Triple("12", 0f, -1f), Triple("3", 1f, 0f), Triple("6", 0f, 1f), Triple("9", -1f, 0f))) {
                Box(Modifier.offset((r + dx * (r - 112) - 50).dp, (r + dy * (r - 112) - 30).dp).size(100.dp, 60.dp), contentAlignment = Alignment.Center) {
                    BasicText(n, style = HudTheme.mont(46f))
                }
            }
        }
    }
}

// ------------------------------------------------------------------ weather

@Composable
fun WeatherApp(weather: HudSnapshot.Weather?) = AppSurface {
    if (weather == null) {
        Column(Modifier.padding(52.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Label("WEATHER")
            BasicText("Waiting for a reading", style = HudTheme.mont(40f, FontWeight.SemiBold, color = HudTheme.inkDim))
        }
        return@AppSurface
    }
    Row(Modifier.fillMaxSize().padding(52.dp), horizontalArrangement = Arrangement.spacedBy(60.dp)) {
        Column(Modifier.width(900.dp).fillMaxHeight(), verticalArrangement = Arrangement.SpaceBetween) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Label(weather.place)
                    Row(verticalAlignment = Alignment.Top) {
                        BasicText("${weather.temperature}", style = HudTheme.mont(200f, tracking = -8f), maxLines = 1)
                        BasicText("°", style = HudTheme.mont(120f))
                    }
                    BasicText(weather.condition, style = HudTheme.mont(34f, tracking = 4f), maxLines = 1)
                    BasicText("H ${weather.high}°   L ${weather.low}°", style = HudTheme.mont(26f, tracking = 3f, color = HudTheme.inkDim))
                }
                Spacer(Modifier.weight(1f))
                HudIcon(weather.icon.vector(), 170f, HudTheme.ink)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                val details = listOfNotNull(weather.feelsLike?.let { "FEELS LIKE" to "$it°" }, weather.humidity?.let { "HUMIDITY" to "$it%" },
                    weather.windKmh?.let { "WIND" to "$it KM/H" }, weather.sunrise?.let { "SUNRISE" to it }, weather.sunset?.let { "SUNSET" to it })
                details.forEachIndexed { i, (label, value) ->
                    if (i > 0) Divider(vertical = true)
                    Column(Modifier.weight(1f).padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        BasicText(label, style = HudTheme.mont(15f, tracking = 2.5f, color = HudTheme.inkDim), maxLines = 1)
                        BasicText(value, style = HudTheme.mont(30f), maxLines = 1)
                    }
                }
            }
            weather.air?.let { air ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val items = listOfNotNull(
                        Triple("AIR", "${air.index}", air.label), Triple("UV", "%.0f".format(air.uv), air.uvLabel),
                        air.pm25?.let { Triple("PM2.5", "%.0f".format(it), "µG/M³") }, air.pollen?.let { Triple("POLLEN", null, it) })
                    items.forEachIndexed { i, (label, value, detail) ->
                        if (i > 0) Divider(vertical = true)
                        Column(Modifier.weight(1f).padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            BasicText(label, style = HudTheme.mont(15f, tracking = 2.5f, color = HudTheme.inkDim))
                            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (value != null) {
                                    BasicText(value, style = HudTheme.mont(30f))
                                    BasicText(detail, style = HudTheme.mont(16f, tracking = 2f, color = HudTheme.accent), maxLines = 1,
                                        modifier = Modifier.padding(bottom = 4.dp))
                                } else BasicText(detail, style = HudTheme.mont(22f), maxLines = 1)
                            }
                        }
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Label("NEXT HOURS")
                Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(20.dp)).padding(vertical = 20.dp)) {
                    for (h in weather.hours.take(12)) Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        BasicText(h.label, style = HudTheme.mont(18f, tracking = 1f, color = HudTheme.inkDim))
                        HudIcon(h.icon.vector(), 30f, HudTheme.ink)
                        BasicText("${h.temperature}°", style = HudTheme.mont(28f))
                        BasicText(if (h.precipitation >= 20) "${h.precipitation}%" else " ", style = HudTheme.mont(16f, color = HudTheme.accent))
                    }
                }
            }
        }
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Label("THIS WEEK")
            val lo = weather.days.minOfOrNull { it.low } ?: 0
            val hi = weather.days.maxOfOrNull { it.high } ?: 1
            weather.days.forEachIndexed { i, d ->
                if (i > 0) Divider()
                Row(Modifier.fillMaxWidth().weight(1f), verticalAlignment = Alignment.CenterVertically) {
                    BasicText(d.label, style = HudTheme.mont(24f, tracking = 2f), modifier = Modifier.width(118.dp), maxLines = 1)
                    Box(Modifier.width(52.dp)) { HudIcon(d.icon.vector(), 32f, HudTheme.ink) }
                    BasicText(if (d.precipitation >= 20) "${d.precipitation}%" else "", style = HudTheme.mont(17f, color = HudTheme.accent), modifier = Modifier.width(58.dp))
                    BasicText("${d.low}°", style = HudTheme.mont(26f, color = HudTheme.inkDim), modifier = Modifier.width(58.dp))
                    BoxWithConstraints(Modifier.weight(1f).height(8.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.1f))) {
                        val span = max(hi - lo, 1).toFloat()
                        val w = maxWidth.value
                        Box(Modifier.offset(((d.low - lo) / span * w).dp).width(((d.high - d.low) / span * w).coerceAtLeast(8f).dp).fillMaxHeight()
                            .background(Brush.horizontalGradient(listOf(Color.White.copy(alpha = 0.6f), HudTheme.accent)), RoundedCornerShape(50)))
                    }
                    BasicText("${d.high}°", style = HudTheme.mont(26f).copy(textAlign = TextAlign.End), modifier = Modifier.width(58.dp))
                }
            }
        }
    }
}

// ------------------------------------------------------------------ activity

@Composable
fun ActivityApp(activity: HudSnapshot.Activity?) = AppSurface {
    if (activity == null) {
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Label("ACTIVITY")
            Spacer(Modifier.height(16.dp))
            BasicText("Allow physical activity in TheHud's settings on the phone", style = HudTheme.mont(34f, FontWeight.SemiBold, color = HudTheme.inkDim))
        }
        return@AppSurface
    }
    Box(Modifier.at(Rect(72f, 56f, 400f, 80f))) { Label("ACTIVITY") }
    Box(Modifier.at(Rect(Offset(90f, 156f), Size(640f, 640f))), contentAlignment = Alignment.Center) {
        ProgressRing(activity.fraction, 44f, Modifier.fillMaxSize())
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            BasicText(activity.steps.grouped(), style = HudTheme.mont(110f, tracking = -3f))
            BasicText("OF ${activity.goal.grouped()} STEPS", style = HudTheme.mont(24f, tracking = 3f, color = HudTheme.inkDim))
        }
    }
    Row(Modifier.at(Rect(Offset(820f, 150f), Size(900f, 120f)))) {
        for ((label, value) in listOf("DISTANCE" to (activity.distanceKm?.let { "%.1f KM".format(it) } ?: "—"),
            "FLOORS" to (activity.floors?.toString() ?: "—"), "GOAL" to "${(activity.fraction * 100).toInt()}%")) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Label(label)
                BasicText(value, style = HudTheme.mont(56f))
            }
        }
    }
    Column(Modifier.at(Rect(Offset(820f, 420f), Size(900f, 400f))), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Label("BY THE HOUR")
        val peak = max(activity.hourly.maxOrNull() ?: 1, 1)
        val now = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
        Row(Modifier.fillMaxWidth().height(260.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (h in 0 until 24) {
                val steps = activity.hourly.getOrElse(h) { 0 }
                Box(Modifier.weight(1f).height(max(6f, 260f * steps / peak).dp).background(when {
                    h == now -> HudTheme.accent; steps > 0 -> Color.White.copy(alpha = 0.55f); else -> Color.White.copy(alpha = 0.1f)
                }, RoundedCornerShape(4.dp)))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            for ((i, t) in listOf("0", "6", "12", "18", "24").withIndex()) {
                BasicText(t, style = HudTheme.mont(16f, color = HudTheme.inkFaint))
                if (i < 4) Spacer(Modifier.weight(1f))
            }
        }
    }
}

// ------------------------------------------------------------------ music

@Composable
fun MusicApp(music: HudSnapshot.NowPlaying?, artwork: ImageBitmap?, hover: Offset?) = AppSurface {
    Artwork(artwork, 36f, Modifier.at(Rect(Offset(72f, 136f), Size(560f, 560f))))
    Column(Modifier.at(Rect(Offset(700f, 140f), Size(1020f, 360f))), verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.Bottom)) {
        Label(if (music?.isPlaying == true) "NOW PLAYING" + (music.app.takeIf { it.isNotEmpty() }?.let { " · ${it.uppercase()}" } ?: "")
            else "MUSIC", accent = music?.isPlaying == true)
        BasicText(music?.title ?: "Nothing playing", style = HudTheme.mont(68f, tracking = -1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
        BasicText(music?.artist ?: "Play something on the phone", style = HudTheme.mont(36f, FontWeight.SemiBold, color = HudTheme.inkDim),
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (!music?.album.isNullOrEmpty()) BasicText(music!!.album, style = HudTheme.mont(26f, FontWeight.SemiBold, color = HudTheme.inkFaint),
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    if (music != null && music.duration > 0) {
        Column(Modifier.at(Rect(Offset(700f, 540f), Size(1020f, 60f))), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            ProgressLine(music.progress, Modifier.fillMaxWidth().height(8.dp))
            Row(Modifier.fillMaxWidth()) {
                BasicText(HudSnapshot.NowPlaying.time(music.elapsed), style = HudTheme.mont(22f, color = HudTheme.inkDim))
                Spacer(Modifier.weight(1f))
                BasicText("−" + HudSnapshot.NowPlaying.time(music.duration - music.elapsed), style = HudTheme.mont(22f, color = HudTheme.inkDim))
            }
        }
    }
    for ((control, frame) in MusicLayout.buttons(appSize, large = true)) {
        MusicButton(control, music?.isPlaying ?: false, true, hover?.let { frame.contains(it) } ?: false, Modifier.at(frame))
    }
}

// ------------------------------------------------------------------ note and captions

@Composable
fun NoteApp(note: HudSnapshot.Note) = AppSurface {
    Box(Modifier.at(Rect(72f, 56f, 600f, 80f))) { Label(if (note.isEditing) "WRITING" else "NOTE", accent = note.isEditing) }
    Box(Modifier.at(Rect(0f, 110f, appSize.width, appSize.height - 40)).clip(RoundedCornerShape(0.dp))) {
        if (note.text.isEmpty() && !note.isEditing) {
            BasicText("Click to write a note", style = HudTheme.mont(64f, FontWeight.SemiBold, color = HudTheme.inkFaint),
                modifier = Modifier.offset(116.dp, 10.dp))
        } else {
            BasicText(buildAnnotatedString {
                append(note.text)
                if (note.isEditing) withStyle(SpanStyle(color = HudTheme.accent)) { append("|") }
            }, style = HudTheme.mont(64f, FontWeight.SemiBold), modifier = Modifier.offset(116.dp, (10 - note.scroll).dp).width(1560.dp))
        }
    }
}

@Composable
fun CaptionsApp(captions: HudSnapshot.Captions) = AppSurface {
    Row(Modifier.at(Rect(Offset(72f, 52f), Size(1648f, 40f))), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(18.dp)) {
        Label("CAPTIONS")
        Spacer(Modifier.weight(1f))
        if (captions.isListening) BasicText(captions.elapsed, style = HudTheme.mont(22f, color = HudTheme.inkDim))
        BasicText(captions.status + if (captions.isListening) "" else " · CLICK TO START",
            style = HudTheme.mont(20f, tracking = 2.5f, color = if (captions.isListening) HudTheme.accent else HudTheme.inkFaint), maxLines = 1)
    }
    Box(Modifier.at(Rect(Offset(120f, 120f), Size(1552f, 760f))), contentAlignment = Alignment.BottomStart) {
        if (captions.lines.isEmpty() && captions.partial.isEmpty()) {
            BasicText(if (captions.isListening) "Listening…" else "Click to start listening",
                style = HudTheme.mont(54f, FontWeight.SemiBold, color = HudTheme.inkFaint))
        } else CaptionLines(captions, 54f, 7)
    }
}

// ------------------------------------------------------------------ maps

private fun HudSnapshot.Maneuver.icon(): ImageVector = when (this) {
    HudSnapshot.Maneuver.straight -> Icons.Rounded.ArrowUpward
    HudSnapshot.Maneuver.left -> Icons.Rounded.TurnLeft
    HudSnapshot.Maneuver.right -> Icons.Rounded.TurnRight
    HudSnapshot.Maneuver.slightLeft -> Icons.Rounded.TurnSlightLeft
    HudSnapshot.Maneuver.slightRight -> Icons.Rounded.TurnSlightRight
    HudSnapshot.Maneuver.uturn -> Icons.Rounded.UTurnLeft
    HudSnapshot.Maneuver.roundabout -> Icons.Rounded.RoundaboutRight
    HudSnapshot.Maneuver.arrive -> Icons.Rounded.Flag
}

private fun Modifier.mapCard(highlighted: Boolean = false): Modifier {
    val shape = RoundedCornerShape(22.dp)
    return this.clip(shape).background(Color.Black.copy(alpha = if (highlighted) 0.9f else 0.8f))
        .border(if (highlighted) 2.dp else 1.dp, if (highlighted) HudTheme.accent.copy(alpha = 0.7f) else HudTheme.edge, shape)
}

/** The map held up alone: the whole canvas is the map, with Maps' search and directions over it. */
@Composable
fun MapsApp(minimap: HudSnapshot.Minimap, maps: HudSnapshot.Maps, ground: ImageBitmap?, standIn: Boolean, hover: Offset?,
            heading: () -> Double = { minimap.heading }) {
    val layout = MapsLayout(maps.results.size, maps.navigation != null)
    val hit = hover?.let { layout.hitTest(it) }
    fun hovered(t: MapsLayout.Target, i: Int = 0) = hit?.target == t && hit.index == i
    Box(Modifier.size(HudTheme.CANVAS_WIDTH.dp, HudTheme.CANVAS_HEIGHT.dp)) {
        Box(Modifier.at(layout.panel)) { MinimapPanel(minimap, ground, standIn, showsHeader = false, heading = heading) }
        val nav = maps.navigation
        if (nav != null) {
            Row(Modifier.at(layout.turnFrame).mapCard().padding(26.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(26.dp)) {
                Box(Modifier.size(148.dp).background(HudTheme.accent, RoundedCornerShape(22.dp)), contentAlignment = Alignment.Center) {
                    HudIcon(if (nav.arrived) Icons.Rounded.Flag else nav.maneuver.icon(), 84f, Color.Black)
                }
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    BasicText(if (nav.arrived) "ARRIVED" else nav.stepDistance, style = HudTheme.mont(60f), maxLines = 1)
                    BasicText(nav.instruction, style = HudTheme.mont(27f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 2,
                        overflow = TextOverflow.Ellipsis)
                }
            }
            Box(Modifier.at(layout.tripFrame).mapCard()) {
                Column(Modifier.padding(start = 26.dp, top = 14.dp).width((layout.tripFrame.width - 26 - 2 * MapsLayout.TRIP_BUTTON_WIDTH - 40).dp)) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        BasicText(nav.remainingTime, style = HudTheme.mont(40f, color = HudTheme.accent), maxLines = 1)
                        BasicText("${nav.remainingDistance} · ARRIVE ${nav.arrival}", style = HudTheme.mont(22f, tracking = 2f, color = HudTheme.inkDim),
                            maxLines = 1, modifier = Modifier.padding(bottom = 6.dp))
                    }
                    BasicText(nav.destination, style = HudTheme.mont(18f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            TripButton(if (maps.driving) Icons.Rounded.DirectionsCar else Icons.Rounded.DirectionsWalk, if (maps.driving) "DRIVE" else "WALK",
                false, hovered(MapsLayout.Target.transport), Modifier.at(layout.transportFrame))
            TripButton(Icons.Rounded.Close, "END", true, hovered(MapsLayout.Target.endRoute), Modifier.at(layout.endFrame))
        } else {
            Row(Modifier.at(layout.searchFrame).mapCard(maps.isEditing || hovered(MapsLayout.Target.search)).padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                HudIcon(Icons.Rounded.Search, 26f, if (maps.isEditing) HudTheme.accent else HudTheme.inkDim)
                if (maps.query.isEmpty() && !maps.isEditing) BasicText("Search Maps", style = HudTheme.mont(28f, FontWeight.SemiBold, color = HudTheme.inkFaint))
                else Row(verticalAlignment = Alignment.CenterVertically) {
                    BasicText(maps.query, style = HudTheme.mont(28f, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false))
                    if (maps.isEditing) Box(Modifier.padding(start = 3.dp).size(3.dp, 34.dp).background(HudTheme.accent))
                }
            }
            if (maps.results.isEmpty()) {
                maps.status?.let { s ->
                    Box(Modifier.at(layout.resultFrame(0)).mapCard().padding(horizontal = 26.dp), contentAlignment = Alignment.CenterStart) {
                        BasicText(s, style = HudTheme.mont(20f, tracking = 3f, color = HudTheme.inkDim))
                    }
                }
            } else maps.results.take(5).forEachIndexed { i, place ->
                Row(Modifier.at(layout.resultFrame(i).let { Rect(it.left, it.top + 4, it.right, it.bottom - 4) })
                    .mapCard(hovered(MapsLayout.Target.result, i)).padding(horizontal = 22.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    HudIcon(Icons.Rounded.Place, 34f, if (i == 0) HudTheme.accent else HudTheme.inkDim)
                    Column(Modifier.weight(1f)) {
                        BasicText(place.name, style = HudTheme.mont(26f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        BasicText(place.detail, style = HudTheme.mont(19f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    BasicText(place.distance, style = HudTheme.mont(22f, color = HudTheme.inkDim))
                }
            }
        }
        ZoomButton(Icons.Rounded.Add, hovered(MapsLayout.Target.zoomIn), Modifier.at(layout.zoomInFrame))
        ZoomButton(Icons.Rounded.Remove, hovered(MapsLayout.Target.zoomOut), Modifier.at(layout.zoomOutFrame))
        val p = layout.panel
        Box(Modifier.at(Rect(Offset(p.right - 28 - 600, p.top + 28), Size(600f, 90f))), contentAlignment = Alignment.TopEnd) {
            Column(Modifier.mapCard().padding(horizontal = 24.dp, vertical = 14.dp), horizontalAlignment = Alignment.End) {
                BasicText(minimap.place, style = HudTheme.mont(24f, tracking = 3f), maxLines = 1)
                if (minimap.speed.isNotEmpty()) BasicText(minimap.speed, style = HudTheme.mont(18f, tracking = 2f, color = HudTheme.inkDim))
            }
        }
    }
}

@Composable
private fun TripButton(icon: ImageVector, title: String, accent: Boolean, hovered: Boolean, modifier: Modifier) {
    val shape = RoundedCornerShape(18.dp)
    Column(modifier.clip(shape).background(if (accent) HudTheme.accent.copy(alpha = if (hovered) 1f else 0.85f) else Color.White.copy(alpha = if (hovered) 0.2f else 0.1f)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        HudIcon(icon, 30f, if (accent) Color.Black else HudTheme.ink)
        BasicText(title, style = HudTheme.mont(14f, tracking = 2f, color = if (accent) Color.Black else HudTheme.ink))
    }
}

@Composable
private fun ZoomButton(icon: ImageVector, hovered: Boolean, modifier: Modifier) {
    Box(modifier.mapCard(hovered), contentAlignment = Alignment.Center) { HudIcon(icon, 30f, HudTheme.ink) }
}

// ------------------------------------------------------------------ the Mac

/** The Mac's picture from HudCast, or what it is waiting for. */
@Composable
fun MacPanel(desktop: HudSnapshot.Desktop, standIn: Boolean, picture: (@Composable () -> Unit)?) {
    val shape = RoundedCornerShape(HudTheme.CORNER.dp)
    BoxWithConstraints(Modifier.fillMaxSize().clip(shape).background(Color.Black).border(1.5.dp, HudTheme.edge, shape), contentAlignment = Alignment.Center) {
        val w = minOf(maxWidth.value, maxHeight.value * desktop.aspect)
        val h = w / desktop.aspect
        if (picture != null) Box(Modifier.size(w.dp, h.dp)) { picture() }
        if (standIn) {
            Box(Modifier.size(w.dp, h.dp).background(Brush.linearGradient(listOf(Color(0xFF2B3550), Color(0xFF14161C))))) {
                Box(Modifier.fillMaxWidth().height(24.dp).background(Color.White.copy(alpha = 0.12f)))
                Box(Modifier.offset((w * 0.12f).dp, (h * 0.2f).dp).size((w * 0.5f).dp, (h * 0.55f).dp)
                    .background(Color(0xFF1E1E22), RoundedCornerShape(12.dp)).border(1.dp, Color.White.copy(alpha = 0.15f), RoundedCornerShape(12.dp)))
            }
        } else if (!desktop.hasPicture) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                HudIcon(Icons.Rounded.DesktopMac, 64f, HudTheme.accent)
                BasicText(desktop.status, style = HudTheme.mont(26f, tracking = 3f))
                BasicText(if (desktop.connected) "The picture starts in a moment" else "Open HudCast on your Mac, on the same Wi-Fi",
                    style = HudTheme.mont(24f, FontWeight.SemiBold, color = HudTheme.inkDim))
            }
        }
    }
}
