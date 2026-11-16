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
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Image
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import com.thehud.core.PhotosLayout
import com.thehud.core.fullAppSize
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// Calendar, Photos and the teleprompter, as HudNewApps.swift draws them: three apps in all three
// sizes — a widget in a slot, the app in the centre, and fullscreen when held.

// ------------------------------------------------------------------ calendar

/** The marks events get, by calendar: the accent first. */
private fun tint(i: Int): Color {
    val colors = listOf(HudTheme.accent, Color(0.45f, 0.72f, 1f), Color(0.95f, 0.45f, 0.45f), Color(0.45f, 0.85f, 0.55f),
        Color(0.75f, 0.55f, 1f), Color.White.copy(alpha = 0.7f))
    return colors[abs(i) % colors.size]
}

@Composable
fun CalendarWidget(agenda: HudSnapshot.Agenda) {
    Column(Modifier.surface()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Label("CALENDAR")
            Spacer(Modifier.weight(1f))
            BasicText(agenda.nextIn, style = HudTheme.mont(16f, tracking = 2f, color = HudTheme.accent))
        }
        val next = agenda.next
        when {
            !agenda.hasAccess -> {
                Spacer(Modifier.weight(1f))
                BasicText("Allow Calendar in TheHud's settings", style = HudTheme.mont(24f, FontWeight.SemiBold, color = HudTheme.inkFaint))
                Spacer(Modifier.weight(1f))
            }
            next != null -> {
                Spacer(Modifier.height(6.dp).weight(1f, fill = false))
                BasicText(next.title, style = HudTheme.mont(40f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                BasicText((if (next.allDay) "ALL DAY" else "${next.time} – ${next.endTime}") +
                    (if (next.location.isEmpty()) "" else "  ·  ${next.location.uppercase()}"),
                    style = HudTheme.mont(18f, tracking = 2f, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 6.dp))
                Spacer(Modifier.weight(1f))
                for (e in agenda.later.take(2)) Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.size(4.dp, 26.dp).background(tint(e.tint), RoundedCornerShape(1.dp)))
                    BasicText(e.title, style = HudTheme.mont(22f, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f))
                    BasicText(e.time, style = HudTheme.mont(22f, color = HudTheme.inkDim))
                }
            }
            else -> {
                Spacer(Modifier.weight(1f))
                BasicText("Nothing else today", style = HudTheme.mont(30f, color = HudTheme.inkDim))
                BasicText(agenda.dayTitle, style = HudTheme.mont(16f, tracking = 2f, color = HudTheme.inkFaint), modifier = Modifier.padding(top = 8.dp))
                Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** The day as a timeline: the hours down the side, events as blocks, and a line at now. */
@Composable
fun CalendarDayView(agenda: HudSnapshot.Agenda, size: Size) = AppSurface {
    val allDay = agenda.today.filter { it.allDay }
    Column(Modifier.fillMaxSize().padding(48.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Label("TODAY")
            Spacer(Modifier.weight(1f))
            BasicText(agenda.nextIn, style = HudTheme.mont(18f, tracking = 2f, color = HudTheme.accent))
        }
        BasicText(agenda.dayTitle, style = HudTheme.mont(44f), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
        if (allDay.isNotEmpty()) Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (e in allDay) Box(Modifier.height(36.dp).background(tint(e.tint), RoundedCornerShape(50)).padding(horizontal = 14.dp),
                contentAlignment = Alignment.Center) {
                BasicText(e.title, style = HudTheme.mont(20f, color = Color.Black), maxLines = 1)
            }
        }
        if (agenda.hasAccess) Timeline(agenda, Modifier.padding(top = 20.dp).fillMaxSize())
        else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            BasicText("Allow Calendar in TheHud's settings to see the day", style = HudTheme.mont(28f, FontWeight.SemiBold, color = HudTheme.inkDim))
        }
    }
}

@Composable
private fun Timeline(agenda: HudSnapshot.Agenda, modifier: Modifier) {
    // The hours shown: from just before the first thing (or now) to just after the last.
    val timed = agenda.today.filter { !it.allDay }
    val first = min(timed.minOfOrNull { it.startMinute } ?: agenda.nowMinute, agenda.nowMinute) / 60
    val last = (max(timed.maxOfOrNull { it.endMinute } ?: agenda.nowMinute, agenda.nowMinute) + 59) / 60
    val start = max(0, min(first, 23) - 1)
    var end = min(24, max(last + 1, start + 6))
    if (end - start > 16) end = start + 16
    BoxWithConstraints(modifier) {
        val height = maxHeight.value
        val width = maxWidth.value
        val perMinute = height / max((end - start) * 60f, 60f)
        fun y(minute: Int) = (minute - start * 60) * perMinute
        val gutter = 92f
        for (hour in start..end) {
            Row(Modifier.offset(y = (y(hour * 60) - 12).dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.width((gutter - 14).dp), contentAlignment = Alignment.CenterEnd) {
                    BasicText("%02d".format(hour % 24), style = HudTheme.mont(20f, color = HudTheme.inkFaint))
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))
            }
        }
        for (e in timed) {
            val top = y(e.startMinute)
            val h = max(y(e.endMinute) - top, 34f)
            val past = e.endMinute <= agenda.nowMinute
            val ink = if (past) HudTheme.inkDim else HudTheme.ink
            Row(Modifier.offset(gutter.dp, top.dp).size((width - gutter).dp, h.dp)
                .background(Color.White.copy(alpha = if (past) 0.04f else 0.09f), RoundedCornerShape(10.dp)),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.width(6.dp).fillMaxHeight().background(tint(e.tint), RoundedCornerShape(2.dp)))
                Column(Modifier.padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    BasicText(e.title, style = HudTheme.mont(if (h > 70) 28f else 22f, color = ink), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (h > 70) BasicText("${e.time} – ${e.endTime}" + (if (e.location.isEmpty()) "" else "  ·  ${e.location}"),
                        style = HudTheme.mont(18f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        if (agenda.nowMinute / 60 in start..end) {
            Row(Modifier.offset((gutter - 7).dp, (y(agenda.nowMinute) - 7).dp).size((width - gutter + 7).dp, 14.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(14.dp).background(HudTheme.accent, RoundedCornerShape(50)))
                Box(Modifier.fillMaxWidth().height(3.dp).background(HudTheme.accent))
            }
        }
    }
}

/** The month: a week to a row, today marked, and the first few things on each day. */
@Composable
fun CalendarMonthView(agenda: HudSnapshot.Agenda) = AppSurface {
    Column(Modifier.fillMaxSize().padding(48.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            BasicText(agenda.monthTitle, style = HudTheme.mont(56f))
            Spacer(Modifier.weight(1f))
            agenda.next?.let { next ->
                BasicText("NEXT  ", style = HudTheme.mont(18f, tracking = 3f, color = HudTheme.inkDim))
                BasicText("${next.title.uppercase()}  ·  ${agenda.nextIn}", style = HudTheme.mont(18f, color = HudTheme.accent), maxLines = 1)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (d in agenda.weekdays) BasicText(d, style = HudTheme.mont(18f, tracking = 3f, color = HudTheme.inkDim), modifier = Modifier.weight(1f))
        }
        val weeks = max(agenda.days.size / 7, 1)
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (week in 0 until weeks) Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (column in 0 until 7) agenda.days.getOrNull(week * 7 + column)?.let { DayCell(it, Modifier.weight(1f).fillMaxHeight()) }
            }
        }
    }
}

@Composable
private fun DayCell(day: HudSnapshot.Agenda.Day, modifier: Modifier) {
    val shape = RoundedCornerShape(14.dp)
    Column(modifier.background(Color.White.copy(alpha = if (day.inMonth) 0.05f else 0.02f), shape)
        .border(2.dp, if (day.isToday) HudTheme.accent.copy(alpha = 0.6f) else Color.Transparent, shape).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(46.dp, 40.dp).background(if (day.isToday) HudTheme.accent else Color.Transparent, RoundedCornerShape(50)),
            contentAlignment = Alignment.Center) {
            BasicText("${day.number}", style = HudTheme.mont(26f, color = when {
                day.isToday -> Color.Black; day.inMonth -> HudTheme.ink; else -> HudTheme.inkFaint }))
        }
        for (t in day.titles) BasicText(t, style = HudTheme.mont(17f, FontWeight.SemiBold,
            color = if (day.inMonth) HudTheme.ink.copy(alpha = 0.85f) else HudTheme.inkFaint), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (day.more > 0) BasicText("+${day.more}", style = HudTheme.mont(16f, color = HudTheme.inkDim))
    }
}

// ------------------------------------------------------------------ photos

/** A photo, or where one will be. */
@Composable
private fun PhotoTile(image: ImageBitmap?, modifier: Modifier, fill: Boolean = true) {
    Box(modifier.background(Color.White.copy(alpha = 0.05f)).clipToBounds(), contentAlignment = Alignment.Center) {
        if (image != null) Image(image, null, Modifier.fillMaxSize(), contentScale = if (fill) ContentScale.Crop else ContentScale.Fit)
        else HudIcon(Icons.Outlined.Image, 34f, HudTheme.inkFaint)
    }
}

@Composable
fun PhotosWidget(photos: HudSnapshot.Photos, image: ImageBitmap?) {
    val shape = RoundedCornerShape(HudTheme.CORNER.dp)
    Box(Modifier.fillMaxSize().clip(shape).border(1.dp, HudTheme.edge, shape)) {
        PhotoTile(image, Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.75f))))
        BasicText(if (!photos.hasAccess) "ALLOW PHOTOS IN SETTINGS" else if (photos.count == 0) "NO PHOTOS" else photos.caption,
            style = HudTheme.mont(16f, tracking = 2.5f), maxLines = 1, modifier = Modifier.align(Alignment.BottomStart).padding(22.dp))
    }
}

/** One photo, large, with when it was taken. */
@Composable
fun PhotoView(photos: HudSnapshot.Photos, image: ImageBitmap?) = AppSurface {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        PhotoTile(image, Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(16.dp)), fill = false)
        Row(verticalAlignment = Alignment.CenterVertically) {
            BasicText(photos.caption, style = HudTheme.mont(22f, tracking = 2.5f), maxLines = 1)
            Spacer(Modifier.weight(1f))
            if (photos.count > 0) BasicText("${photos.current + 1} / ${photos.count}", style = HudTheme.mont(20f, color = HudTheme.inkDim))
        }
    }
}

/** Fullscreen: a grid of the library, the picked one marked; opened, that one alone. */
@Composable
fun PhotosGallery(photos: HudSnapshot.Photos, images: Map<Int, ImageBitmap>, size: Size = fullAppSize, hover: Offset? = null) {
    if (photos.viewing) return PhotoView(photos.copy(current = photos.selected), images[photos.selected])
    AppSurface {
        Row(Modifier.at(Rect(Offset(56f, 44f), Size(size.width - 112, 40f))), verticalAlignment = Alignment.CenterVertically) {
            Label("PHOTOS")
            Spacer(Modifier.weight(1f))
            BasicText(photos.caption, style = HudTheme.mont(20f, tracking = 2.5f, color = HudTheme.inkDim))
        }
        if (!photos.hasAccess || photos.count == 0) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            BasicText(if (photos.hasAccess) "No photos on the phone" else "Allow Photos in TheHud's settings to see them here",
                style = HudTheme.mont(30f, FontWeight.SemiBold, color = HudTheme.inkDim))
        }
        for (slot in 0 until PhotosLayout.COLUMNS * PhotosLayout.ROWS) {
            val index = photos.scrollRow * PhotosLayout.COLUMNS + slot
            if (index >= photos.count) break
            val frame = PhotosLayout.tile(slot, size)
            val picked = index == photos.selected
            val hovered = hover?.let { frame.contains(it) } ?: false
            val shape = RoundedCornerShape(12.dp)
            PhotoTile(images[index], Modifier.at(frame).clip(shape)
                .border(if (picked) 5.dp else 3.dp, if (picked) HudTheme.accent else if (hovered) Color.White.copy(alpha = 0.6f) else Color.Transparent, shape))
        }
    }
}

// ------------------------------------------------------------------ teleprompter

/** The note, scrolling on its own at the phone's speed, with a mark at the reading line. */
@Composable
fun PrompterView(text: String, prompter: HudSnapshot.Prompter, fontSize: Float, showsHeader: Boolean = true) = AppSurface {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(prompter.isRunning) {
        now = System.currentTimeMillis()
        while (prompter.isRunning) withFrameMillis { now = System.currentTimeMillis() }
    }
    var textHeight by remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxSize().padding(horizontal = 64.dp, vertical = 24.dp)
        .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
        .drawWithContent {
            drawContent()
            // Faded in at the top and out at the bottom.
            drawRect(Brush.verticalGradient(0f to Color.Transparent, 0.18f to Color.Black, 0.82f to Color.Black, 1f to Color.Transparent),
                blendMode = BlendMode.DstIn)
        }
        .clipToBounds()) {
        val readingLine = maxHeight.value * 0.32f
        val offset = min(prompter.offset(now), max(textHeight, 0f))
        BasicText(text.ifEmpty { "Write in the note, and it scrolls here." },
            style = HudTheme.mont(fontSize, FontWeight.SemiBold, color = if (text.isEmpty()) HudTheme.inkFaint else HudTheme.ink)
                .copy(lineHeight = androidx.compose.ui.unit.TextUnit(fontSize * 1.28f, androidx.compose.ui.unit.TextUnitType.Sp)),
            modifier = Modifier.offset(36.dp, (readingLine - offset).dp).width((maxWidth.value - 36).dp).wrapContentHeight(unbounded = true)
                .onSizeChanged { textHeight = with(density) { it.height.toDp().value } })
        // The reading line: the words to say are level with it.
        Box(Modifier.offset(y = readingLine.dp).size(8.dp, (fontSize * 1.1f).dp).background(HudTheme.accent))
    }
    if (showsHeader) Row(Modifier.fillMaxWidth().padding(start = 40.dp, end = 40.dp, top = 28.dp), verticalAlignment = Alignment.CenterVertically) {
        Label("TELEPROMPTER", accent = prompter.isRunning)
        Spacer(Modifier.weight(1f))
        BasicText(if (prompter.isRunning) "SPEED ${prompter.step}" else "PAUSED · SPEED ${prompter.step}",
            style = HudTheme.mont(16f, tracking = 2f, color = HudTheme.inkDim))
    }
}

@Composable
fun PrompterWidget(text: String, prompter: HudSnapshot.Prompter) {
    Box(Modifier.fillMaxSize()) {
        PrompterView(text, prompter, 30f, showsHeader = false)
        Box(Modifier.padding(22.dp)) { Label("PROMPTER", accent = prompter.isRunning) }
    }
}
