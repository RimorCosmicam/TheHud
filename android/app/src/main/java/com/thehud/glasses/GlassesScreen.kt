package com.thehud.glasses

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.outlined.AcUnit
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Dehaze
import androidx.compose.material.icons.outlined.Grain
import androidx.compose.material.icons.outlined.NightsStay
import androidx.compose.material.icons.outlined.Thunderstorm
import androidx.compose.material.icons.outlined.Umbrella
import androidx.compose.material.icons.outlined.WbCloudy
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.Image
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.thehud.core.BrowserMetrics
import com.thehud.core.GlassesLayout
import com.thehud.core.HudPanelKind
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import com.thehud.core.WeatherIcon

// The glasses, drawn at canvas units: inside GlassesRoot one dp is one point of the 1920x1080
// canvas, so these numbers are the iPhone app's.

/** Puts something at a canvas rectangle. */
fun Modifier.at(r: Rect) = this.offset(r.left.dp, r.top.dp).size(r.width.dp, r.height.dp)

private val panelShape = RoundedCornerShape(HudTheme.CORNER.dp)

/** Everything on the glasses: black, which the glasses show as nothing, and what is placed on it. */
@Composable
fun GlassesScreen(
    snapshot: HudSnapshot,
    layout: GlassesLayout,
    /** The live page for the browser; null draws a stand-in (stills). */
    page: (@Composable () -> Unit)? = null,
) {
    Box(Modifier.size(HudTheme.CANVAS_WIDTH.dp, HudTheme.CANVAS_HEIGHT.dp).background(Color.Black)) {
        for ((kind, frame) in layout.bigFrames) {
            Box(Modifier.at(frame)) {
                when (kind) {
                    HudPanelKind.browser -> BrowserPanel(snapshot.browser, layout, snapshot.cursor, page)
                    else -> Placeholder(kind)
                }
            }
        }
        for ((kind, frame) in layout.widgetFrames) {
            Box(Modifier.at(frame)) { Widget(kind, snapshot) }
        }
        layout.soloWidgetFrame?.let { frame ->
            layout.solo?.let { kind -> Box(Modifier.at(frame)) { SoloApp(kind, snapshot) } }
        }
        snapshot.cursor?.let { CursorArrow(it) }
    }
}

// ------------------------------------------------------------------ pieces

@Composable
fun Label(text: String, accent: Boolean = false) {
    BasicText(text, style = HudTheme.mont(16f, tracking = 3f, color = if (accent) HudTheme.accent else HudTheme.inkDim),
        maxLines = 1)
}

/** The widget's own surface, filling its slot. */
fun Modifier.surface(padding: Float = 26f) = this.fillMaxSize()
    .clip(panelShape).background(HudTheme.surface)
    .border(1.dp, HudTheme.edge, panelShape)
    .padding(padding.dp)

@Composable
private fun Icon(vector: ImageVector, size: Float, color: Color = HudTheme.ink) {
    Image(vector, null, Modifier.size(size.dp), colorFilter = ColorFilter.tint(color))
}

fun WeatherIcon.vector(): ImageVector = when (this) {
    WeatherIcon.sun -> Icons.Outlined.WbSunny
    WeatherIcon.moon -> Icons.Outlined.NightsStay
    WeatherIcon.partly -> Icons.Outlined.WbCloudy
    WeatherIcon.cloud -> Icons.Outlined.Cloud
    WeatherIcon.fog -> Icons.Outlined.Dehaze
    WeatherIcon.drizzle -> Icons.Outlined.Grain
    WeatherIcon.rain -> Icons.Outlined.Umbrella
    WeatherIcon.snow -> Icons.Outlined.AcUnit
    WeatherIcon.storm -> Icons.Outlined.Thunderstorm
}

@Composable
fun Widget(kind: HudPanelKind, snapshot: HudSnapshot) {
    when (kind) {
        HudPanelKind.clock -> ClockWidget(snapshot.clock, snapshot.timer)
        HudPanelKind.weather -> WeatherWidget(snapshot.weather)
        HudPanelKind.note -> NoteWidget(snapshot.note)
        else -> Placeholder(kind)
    }
}

@Composable
private fun Placeholder(kind: HudPanelKind) {
    Column(Modifier.surface()) {
        Label(kind.title)
        Spacer(Modifier.height(10.dp))
        BasicText("Coming to Android", style = HudTheme.mont(24f, FontWeight.SemiBold, color = HudTheme.inkFaint))
    }
}

// ------------------------------------------------------------------ clock

@Composable
fun ClockWidget(clock: HudSnapshot.Clock, timer: HudSnapshot.TimerReading) {
    Column(Modifier.surface()) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.offset(y = (-12).dp)) {
            BasicText(clock.time, style = HudTheme.mont(112f, tracking = -4f), maxLines = 1)
            clock.meridiem?.let { BasicText(it, style = HudTheme.mont(30f), modifier = Modifier.padding(bottom = 22.dp)) }
        }
        BasicText("${clock.weekday}  ·  ${clock.date}", style = HudTheme.mont(19f, tracking = 2.5f, color = HudTheme.inkDim),
            maxLines = 1, modifier = Modifier.offset(y = (-12).dp))
        Spacer(Modifier.weight(1f))
        // A running timer outranks the calendar: it is the thing with a deadline.
        if (timer.state != HudSnapshot.TimerState.idle) {
            MarkRow(if (timer.state == HudSnapshot.TimerState.done) "TIME'S UP" else "TIMER",
                when { timer.state == HudSnapshot.TimerState.paused -> "Paused"; timer.isStopwatch -> "Stopwatch"; else -> "Running" },
                timer.text)
        } else clock.nextEvent?.let { MarkRow("NEXT", it, clock.nextEventTime) }
    }
}

@Composable
private fun MarkRow(label: String, title: String, trailing: String?) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(4.dp, 44.dp).background(HudTheme.accent, RoundedCornerShape(1.dp)))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            BasicText(label, style = HudTheme.mont(14f, tracking = 3f, color = HudTheme.inkDim))
            BasicText(title, style = HudTheme.mont(24f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        trailing?.let { BasicText(it, style = HudTheme.mont(28f)) }
    }
}

// ------------------------------------------------------------------ weather

@Composable
fun WeatherWidget(weather: HudSnapshot.Weather?) {
    Column(Modifier.surface()) {
        if (weather == null) {
            Label("WEATHER")
            Spacer(Modifier.height(10.dp))
            BasicText("Waiting for a reading", style = HudTheme.mont(24f, FontWeight.SemiBold, color = HudTheme.inkDim))
            return@Column
        }
        Row(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.Top, modifier = Modifier.offset(y = (-10).dp)) {
                BasicText("${weather.temperature}", style = HudTheme.mont(84f, tracking = -3f))
                BasicText("°", style = HudTheme.mont(50f))
            }
            Spacer(Modifier.weight(1f))
            Icon(weather.icon.vector(), 54f)
        }
        BasicText(weather.condition, style = HudTheme.mont(20f, tracking = 3f), maxLines = 1)
        BasicText("H ${weather.high}°  L ${weather.low}°  ·  ${weather.place}",
            style = HudTheme.mont(15f, tracking = 2f, color = HudTheme.inkDim), maxLines = 1,
            modifier = Modifier.padding(top = 4.dp))
        Spacer(Modifier.weight(1f))
        // The next hours, so the slot answers "will it rain on the way".
        Row(Modifier.fillMaxWidth()) {
            for (hour in weather.hours.drop(1).take(4)) {
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    BasicText(hour.label, style = HudTheme.mont(14f, tracking = 1f, color = HudTheme.inkDim))
                    Icon(hour.icon.vector(), 24f)
                    BasicText("${hour.temperature}°", style = HudTheme.mont(20f))
                }
            }
        }
    }
}

// ------------------------------------------------------------------ note

@Composable
fun NoteWidget(note: HudSnapshot.Note, lines: Int = 6, size: Float = 24f) {
    Column(Modifier.surface(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Label(if (note.isEditing) "WRITING" else "NOTE", accent = note.isEditing)
        if (note.text.isEmpty() && !note.isEditing) {
            BasicText("Click to write a note", style = HudTheme.mont(size, FontWeight.SemiBold, color = HudTheme.inkFaint))
        } else {
            // While writing, the end of the text is what matters: show the last lines.
            val text = if (note.isEditing) note.text.lines().takeLast(lines).joinToString("\n") else note.text
            BasicText(buildAnnotatedString {
                append(text)
                if (note.isEditing) withStyle(SpanStyle(color = HudTheme.accent)) { append("|") }
            }, style = HudTheme.mont(size, FontWeight.SemiBold).copy(lineHeight = HudTheme.mont(size).lineHeight * 1.12f),
                maxLines = lines, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.offset(y = (if (note.isEditing) 0f else -note.scroll).dp))
        }
    }
}

// ------------------------------------------------------------------ solo apps

/** A widget held up alone, at the size of the whole glasses. */
@Composable
fun SoloApp(kind: HudPanelKind, snapshot: HudSnapshot) {
    when (kind) {
        HudPanelKind.clock -> ClockApp(snapshot)
        HudPanelKind.weather -> WeatherApp(snapshot.weather)
        HudPanelKind.note -> NoteWidget(snapshot.note, lines = 16, size = 34f)
        else -> Placeholder(kind)
    }
}

@Composable
private fun ClockApp(snapshot: HudSnapshot) {
    val clock = snapshot.clock
    val timer = snapshot.timer
    Column(Modifier.surface(56f)) {
        Label("CLOCK")
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            BasicText(clock.time, style = HudTheme.mont(300f, tracking = -12f), maxLines = 1)
            clock.meridiem?.let { BasicText(it, style = HudTheme.mont(70f), modifier = Modifier.padding(bottom = 64.dp)) }
        }
        BasicText("${clock.weekday}  ·  ${clock.date}", style = HudTheme.mont(36f, tracking = 5f, color = HudTheme.inkDim))
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp, 90.dp).background(HudTheme.accent, RoundedCornerShape(2.dp)))
            Spacer(Modifier.width(24.dp))
            Column(Modifier.weight(1f)) {
                BasicText(if (timer.state == HudSnapshot.TimerState.done) "TIME'S UP" else "TIMER",
                    style = HudTheme.mont(20f, tracking = 4f, color = HudTheme.inkDim))
                BasicText(when (timer.state) {
                    HudSnapshot.TimerState.idle -> "Click to start"
                    HudSnapshot.TimerState.running -> "Running · click to pause"
                    HudSnapshot.TimerState.paused -> "Paused · click to go on"
                    HudSnapshot.TimerState.done -> "Click to start again"
                }, style = HudTheme.mont(30f, FontWeight.SemiBold, color = HudTheme.inkDim))
            }
            BasicText(timer.text, style = HudTheme.mont(110f, tracking = -3f))
        }
        timer.progress?.let { p ->
            Box(Modifier.fillMaxWidth().padding(top = 20.dp).height(6.dp).background(HudTheme.inkFaint, RoundedCornerShape(3.dp))) {
                Box(Modifier.fillMaxWidth(p).fillMaxHeight().background(HudTheme.accent, RoundedCornerShape(3.dp)))
            }
        }
    }
}

@Composable
private fun WeatherApp(weather: HudSnapshot.Weather?) {
    Column(Modifier.surface(56f)) {
        Label("WEATHER")
        if (weather == null) {
            Spacer(Modifier.height(20.dp))
            BasicText("Waiting for a reading", style = HudTheme.mont(40f, FontWeight.SemiBold, color = HudTheme.inkDim))
            return@Column
        }
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(verticalAlignment = Alignment.Top) {
                BasicText("${weather.temperature}", style = HudTheme.mont(260f, tracking = -10f))
                BasicText("°", style = HudTheme.mont(140f))
            }
            Spacer(Modifier.width(48.dp))
            Column {
                Icon(weather.icon.vector(), 130f)
                Spacer(Modifier.height(14.dp))
                BasicText(weather.condition, style = HudTheme.mont(40f, tracking = 5f))
                BasicText("H ${weather.high}°  L ${weather.low}°  ·  ${weather.place}",
                    style = HudTheme.mont(26f, tracking = 3f, color = HudTheme.inkDim))
            }
        }
        Spacer(Modifier.weight(1f))
        Row(Modifier.fillMaxWidth()) {
            for (hour in weather.hours) {
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    BasicText(hour.label, style = HudTheme.mont(24f, tracking = 2f, color = HudTheme.inkDim))
                    Icon(hour.icon.vector(), 52f)
                    BasicText("${hour.temperature}°", style = HudTheme.mont(40f))
                }
            }
        }
    }
}

// ------------------------------------------------------------------ browser

/**
 * The browser: the page under one glass bar, Safari's compact layout as on the iPhone. The bar is
 * the page's title at rest; with the cursor on it, back, forward, new tab and reload show at its ends.
 */
@Composable
fun BrowserPanel(browser: HudSnapshot.Browser, layout: GlassesLayout, cursor: Offset?, page: (@Composable () -> Unit)?) {
    if (browser.isFullscreen) {
        Box(Modifier.fillMaxSize().background(Color.Black)) { page?.invoke() ?: PageStandIn() }
        return
    }
    val hovering = layout.isOverBar(cursor)
    val hoveredTab = layout.tabAt(cursor)
    Box(Modifier.fillMaxSize().clip(panelShape).background(Color.Black).border(1.dp, HudTheme.edge, panelShape)) {
        Box(Modifier.fillMaxSize().padding(top = BrowserMetrics.contentTopInset.dp)) { page?.invoke() ?: PageStandIn() }
        val bar = layout.barFrame ?: return@Box
        Box(Modifier.padding(BrowserMetrics.BAR_INSET.dp).fillMaxWidth().height(BrowserMetrics.BAR_HEIGHT.dp)) {
            Bar(browser, bar.width, hovering && !browser.isEditingAddress, hoveredTab, layout.tabCount)
        }
    }
}

@Composable
private fun Bar(browser: HudSnapshot.Browser, width: Float, showsButtons: Boolean, hoveredTab: Int?, tabCount: Int) {
    val capsule = RoundedCornerShape(50)
    val b = BrowserMetrics.BUTTON_WIDTH
    Box(Modifier.fillMaxSize().clip(capsule).background(Color.White.copy(alpha = 0.10f))
        .border(1.5.dp, Color.White.copy(alpha = if (showsButtons) 0.42f else 0.26f), capsule)) {
        if (browser.isEditingAddress) {
            Row(Modifier.offset(x = (b * 2).dp).width(maxOf(width - b * 4, 0f).dp).fillMaxHeight().padding(horizontal = 30.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Search, 26f, HudTheme.inkDim)
                Spacer(Modifier.width(14.dp))
                BasicText(buildAnnotatedString {
                    if (browser.url.isEmpty()) {
                        withStyle(SpanStyle(color = HudTheme.accent)) { append("▏") }
                        withStyle(SpanStyle(color = HudTheme.inkFaint)) { append("Search Google or enter address") }
                    } else {
                        append(browser.url)
                        withStyle(SpanStyle(color = HudTheme.accent)) { append("▏") }
                    }
                }, style = HudTheme.mont(24f, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        } else {
            val segments = BrowserMetrics.tabSegments(width, tabCount, browser.activeTab)
            segments.forEachIndexed { i, (x, w) ->
                Tab(browser, i, tabCount, hoveredTab == i, Modifier.offset(x = x.dp).width(w.dp).fillMaxHeight())
            }
        }
        if (showsButtons) {
            Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                Nav(Icons.Rounded.ChevronLeft, browser.canGoBack)
                Nav(Icons.Rounded.ChevronRight, browser.canGoForward)
                Spacer(Modifier.weight(1f))
                Nav(Icons.Rounded.Add, tabCount < BrowserMetrics.MAX_TABS)
                Nav(if (browser.loading == null) Icons.Rounded.Refresh else Icons.Rounded.Close, true)
            }
        }
        browser.loading?.let { p ->
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth(p).height(3.dp).background(HudTheme.accent))
        }
    }
}

@Composable
private fun Nav(icon: ImageVector, enabled: Boolean) {
    Box(Modifier.width(BrowserMetrics.BUTTON_WIDTH.dp).fillMaxHeight(), contentAlignment = Alignment.Center) {
        Icon(icon, 32f, if (enabled) HudTheme.ink else HudTheme.inkFaint)
    }
}

@Composable
private fun Tab(browser: HudSnapshot.Browser, index: Int, count: Int, hovered: Boolean, modifier: Modifier) {
    val active = index == browser.activeTab
    val several = count > 1
    Box(modifier, contentAlignment = if (several) Alignment.CenterStart else Alignment.Center) {
        if (several && active) {
            Box(Modifier.fillMaxSize().padding(vertical = 8.dp, horizontal = 4.dp)
                .background(Color.White.copy(alpha = 0.11f), RoundedCornerShape(50)))
        }
        if (several && !active && index > 0 && index - 1 != browser.activeTab) {
            Box(Modifier.size(1.dp, 26.dp).background(Color.White.copy(alpha = 0.14f)))
        }
        Row(Modifier.padding(start = if (several) BrowserMetrics.CLOSE_WIDTH.dp else 16.dp, end = 16.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (active) {
                val home = browser.url.isEmpty()
                Icon(if (home) Icons.Rounded.Search else Icons.Rounded.Language, 24f, HudTheme.inkDim)
                Spacer(Modifier.width(12.dp))
                BasicText(when { home -> "Search or enter website name"; browser.title.isNotEmpty() -> browser.title; else -> browser.url },
                    style = HudTheme.mont(24f, FontWeight.SemiBold, color = HudTheme.ink.copy(alpha = if (home) 0.55f else 0.9f)),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            } else {
                BasicText(browser.tabs.getOrElse(index) { "" },
                    style = HudTheme.mont(20f, FontWeight.SemiBold, color = HudTheme.ink.copy(alpha = if (hovered) 0.85f else 0.5f)),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (several && hovered) {
            Box(Modifier.width(BrowserMetrics.CLOSE_WIDTH.dp).fillMaxHeight(), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Close, 22f, HudTheme.ink.copy(alpha = 0.8f))
            }
        }
    }
}

/** A page for the stills, where no web view runs. */
@Composable
fun PageStandIn() {
    Column(Modifier.fillMaxSize().background(Color(0xFF121214)).padding(horizontal = 54.dp, vertical = 30.dp)) {
        BasicText("Android", style = HudTheme.mont(52f, tracking = -1f))
        Spacer(Modifier.height(10.dp))
        BasicText("DEVELOPERS", style = HudTheme.mont(16f, tracking = 3f, color = HudTheme.accent))
        Spacer(Modifier.height(26.dp))
        BasicText("Build apps that give your users seamless experiences from phones to tablets, watches, and more.",
            style = HudTheme.mont(25f, FontWeight.Normal, color = HudTheme.ink.copy(alpha = 0.88f)))
        Spacer(Modifier.height(34.dp))
        BasicText("OVERVIEW", style = HudTheme.mont(17f, tracking = 3f, color = HudTheme.inkDim))
        Spacer(Modifier.height(16.dp))
        repeat(4) { row ->
            Box(Modifier.fillMaxWidth(if (row == 3) 0.4f else 1f).height(15.dp)
                .background(Color.White.copy(alpha = 0.14f), RoundedCornerShape(2.dp)))
            Spacer(Modifier.height(15.dp))
        }
    }
}

// ------------------------------------------------------------------ cursor

@Composable
fun CursorArrow(at: Offset) {
    Canvas(Modifier.offset(at.x.dp, at.y.dp).size(26.dp, 38.dp)) {
        val s = size.width / 26f
        val arrow = Path().apply {
            moveTo(0f, 0f); lineTo(0f, 30f * s); lineTo(8f * s, 23f * s); lineTo(13f * s, 34f * s)
            lineTo(19f * s, 31f * s); lineTo(14f * s, 21f * s); lineTo(23f * s, 20f * s); close()
        }
        drawPath(arrow, Color.Black.copy(alpha = 0.85f), style = Stroke(width = 5f * s, join = StrokeJoin.Round))
        drawPath(arrow, Color.White)
    }
}
