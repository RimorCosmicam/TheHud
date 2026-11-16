package com.thehud.glasses

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Search
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import com.thehud.core.YouTubeAppLayout
import com.thehud.core.YouTubeVideo
import kotlin.math.abs
import kotlin.math.min

// YouTube on the glasses, as YouTubeViews.swift draws it. The video itself is one layer under
// everything, never moved between views, only placed: these leave a hole where it shows.

/** Where the live video shows now: the whole canvas while watching, the tile while browsing, its slot as a widget, or nowhere. */
fun youtubeVideoBox(snapshot: HudSnapshot, layout: com.thehud.core.GlassesLayout): Pair<Rect, Float>? {
    val y = snapshot.youtube
    if (!y.hasVideo || layout.clearView || layout.fullscreen) return null
    if (layout.solo == com.thehud.core.HudPanelKind.youtube) {
        if (y.page == HudSnapshot.YouTube.Page.player) return Rect(Offset.Zero, Size(HudTheme.CANVAS_WIDTH, HudTheme.CANVAS_HEIGHT)) to 0f
        val inset = com.thehud.core.GlassesLayout.safeFrame.topLeft
        return YouTubeAppLayout.tileVideo.translate(inset) to 12f
    }
    if (layout.solo != null) return null
    layout.centreApp?.let { (kind, frame) ->
        if (kind == com.thehud.core.HudPanelKind.youtube) {
            val box = if (y.page == HudSnapshot.YouTube.Page.player) YouTubeAppLayout.centreVideo(frame.size) else YouTubeAppLayout.tileVideo(frame.size)
            return box.translate(frame.topLeft) to 12f
        }
    }
    return layout.widgetFrames.firstOrNull { it.first == com.thehud.core.HudPanelKind.youtube }?.second?.let { it to HudTheme.CORNER }
}

/** 16:9 inside a box. */
fun fit16x9(size: Size): Size { val s = min(size.width / 16, size.height / 9); return Size(16 * s, 9 * s) }

/** The size the player's page is always laid out at. */
private val PLAYER_PAGE = Size(1280f, 720f)

/**
 * The one video layer: placed in its box, or parked off the canvas, never taken out of its view.
 *
 * The page itself never changes size: YouTube's player keeps drawing at the size it first had,
 * so a page grown from a slot to the whole canvas played in its top left corner. It stays
 * 1280 by 720 and its picture is scaled into the box instead.
 */
@Composable
fun YouTubeVideoLayer(box: Rect?, corner: Float, content: @Composable () -> Unit) {
    val b = box ?: Rect(Offset(-1400f, 0f), PLAYER_PAGE)
    val v = fit16x9(b.size)
    val scale = v.width / PLAYER_PAGE.width
    Box(Modifier.at(b).clip(RoundedCornerShape(corner.dp)).background(Color.Black), contentAlignment = Alignment.Center) {
        Box(Modifier.size(v.width.dp, v.height.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.requiredSize(PLAYER_PAGE.width.dp, PLAYER_PAGE.height.dp)
                .graphicsLayer { scaleX = scale; scaleY = scale }) { content() }
        }
    }
}

@Composable
private fun StandInFrame(modifier: Modifier) {
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val s = fit16x9(Size(maxWidth.value, maxHeight.value))
        Box(Modifier.size(s.width.dp, s.height.dp).background(Brush.linearGradient(listOf(Color(0xFF1F2A3D), Color(0xFF0D0F14))))) {
            Box(Modifier.align(Alignment.Center).padding(start = (s.width * 0.36f).dp).size((s.height * 0.5f).dp)
                .background(Brush.radialGradient(listOf(Color(0x80D98C40), Color.Transparent)), RoundedCornerShape(50)))
        }
    }
}

/** A widget's or app's hole for the video, when the video is live under it. */
private fun Modifier.hole(rect: Rect?, corner: Float): Modifier = if (rect == null) this else
    this.graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen).drawWithContent {
        drawContent()
        drawRoundRect(Color.Black, rect.topLeft, rect.size, CornerRadius(corner, corner), blendMode = BlendMode.Clear)
    }

@Composable
fun YouTubeWidget(y: HudSnapshot.YouTube, live: Boolean, standIn: Boolean) {
    val shape = RoundedCornerShape(HudTheme.CORNER.dp)
    Box(Modifier.fillMaxSize().clip(shape).background(if (live && y.hasVideo) Color.Transparent else Color.Black)
        .border(1.dp, HudTheme.edge, shape)) {
        if (y.hasVideo) {
            if (!live && standIn) StandInFrame(Modifier.fillMaxSize())
            Column(Modifier.align(Alignment.BottomStart).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))))
                .padding(start = 20.dp, end = 20.dp, top = 34.dp, bottom = 18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                BasicText(if (y.isAd) "AD" else y.title, style = HudTheme.mont(18f, color = if (y.isAd) HudTheme.accent else HudTheme.ink),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (!y.isLive) ProgressLine(y.progress, Modifier.fillMaxWidth().height(4.dp))
            }
            if (y.notice.isNotEmpty()) {
                BasicText(y.notice, style = HudTheme.mont(16f, FontWeight.SemiBold, color = HudTheme.inkDim).copy(textAlign = TextAlign.Center),
                    modifier = Modifier.align(Alignment.Center).padding(24.dp))
            } else if (!y.isPlaying) {
                Box(Modifier.align(Alignment.Center)) { HudIcon(Icons.Rounded.Pause, 52f, Color.White.copy(alpha = 0.9f)) }
            }
        } else {
            Column(Modifier.padding(26.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Label("YOUTUBE")
                BasicText("Hold to open and pick something", style = HudTheme.mont(18f, FontWeight.SemiBold, color = HudTheme.inkFaint))
            }
        }
    }
}

@Composable
fun YouTubeApp(y: HudSnapshot.YouTube, live: Boolean, standIn: Boolean, hover: Offset?, size: Size = YouTubeAppLayout.size) {
    val target = hover?.let { YouTubeAppLayout.target(it, y, size) }
    val shape = RoundedCornerShape(HudTheme.CORNER.dp)
    val wide = YouTubeAppLayout.wide(size)
    Box(Modifier.fillMaxSize().hole(if (live && y.hasVideo) YouTubeAppLayout.tileVideo(size) else null, 12f)
        .clip(shape).background(HudTheme.surface).border(1.dp, HudTheme.edge, shape)) {
        y.tabs.forEachIndexed { i, tab ->
            YtChip(tab.title, tab == HudSnapshot.YouTube.Tab.search, y.tab == tab, target == YouTubeAppLayout.Target.Tab(tab),
                Modifier.at(YouTubeAppLayout.tabFrame(i, y.tabs)))
        }
        if (y.tab == HudSnapshot.YouTube.Tab.search) {
            val last = YouTubeAppLayout.tabFrame(y.tabs.size - 1, y.tabs)
            Box(Modifier.at(Rect(Offset(last.right + 24, last.top),
                Size(maxOf((if (wide) YouTubeAppLayout.nowPlayingTile(size).left else size.width) - last.right - 48, 0f), last.height))),
                contentAlignment = Alignment.CenterStart) {
                BasicText(buildString {
                    if (y.query.isEmpty() && !y.isEditingQuery) append("Search from the phone") else append("“${y.query}”")
                }, style = HudTheme.mont(26f, if (y.query.isEmpty()) FontWeight.SemiBold else FontWeight.Black,
                    color = if (y.query.isEmpty()) HudTheme.inkFaint else HudTheme.ink).let { s ->
                    if (y.isEditingQuery) s.copy(color = HudTheme.ink) else s
                }, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (y.hasVideo) NowPlayingTile(y, live, standIn, target == YouTubeAppLayout.Target.NowPlaying, Modifier.at(YouTubeAppLayout.nowPlayingTile(size)))

        val list = y.list(y.tab)
        if (list.isEmpty()) {
            Box(Modifier.at(Rect(Offset(72f, 150f), Size(size.width - 144, size.height - 300))), contentAlignment = Alignment.Center) {
                BasicText(when {
                    y.loading -> "Loading…"
                    y.problem.isNotEmpty() -> y.problem
                    y.tab == HudSnapshot.YouTube.Tab.search -> if (y.query.isEmpty()) "Tap SEARCH on the phone and type" else "Nothing found"
                    y.tab == HudSnapshot.YouTube.Tab.subscriptions -> "Nothing new from your subscriptions"
                    else -> "Nothing here yet"
                }, style = HudTheme.mont(30f, FontWeight.SemiBold, color = HudTheme.inkFaint))
            }
        } else {
            val columns = YouTubeAppLayout.columns(size)
            val visibleRows = YouTubeAppLayout.visibleRows(size)
            val first = y.scrollRow * columns
            for (slot in 0 until columns * visibleRows) {
                val video = list.getOrNull(first + slot) ?: continue
                val frame = YouTubeAppLayout.cardFrame(slot, size)
                VideoCard(video, y.queue.indexOf(video).takeIf { it >= 0 }, video.id == y.videoId,
                    target == YouTubeAppLayout.Target.Card(first + slot), Modifier.at(frame), frame.width)
            }
            val rows = (list.size + columns - 1) / columns
            if (rows > visibleRows && size == YouTubeAppLayout.size) {
                BasicText("ROWS ${y.scrollRow + 1}–${min(y.scrollRow + 2, rows)} OF $rows · SCROLL FOR MORE",
                    style = HudTheme.mont(18f, tracking = 3f, color = HudTheme.inkFaint), modifier = Modifier.at(Rect(72f, 872f, 1720f, 902f)))
            }
        }
    }
}

@Composable
private fun NowPlayingTile(y: HudSnapshot.YouTube, live: Boolean, standIn: Boolean, lit: Boolean, modifier: Modifier) {
    Row(modifier.background(Color.White.copy(alpha = if (lit) 0.14f else 0f), RoundedCornerShape(14.dp)).padding(2.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(142.dp, 80.dp).clip(RoundedCornerShape(12.dp))) {
            if (!live) { Box(Modifier.fillMaxSize().background(Color.Black)); if (standIn) StandInFrame(Modifier.fillMaxSize()) }
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            BasicText(if (y.isPlaying) "NOW PLAYING" else "PAUSED", style = HudTheme.mont(14f, tracking = 3f, color = if (y.isPlaying) HudTheme.accent else HudTheme.inkDim))
            BasicText(y.title, style = HudTheme.mont(20f), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun YtChip(text: String, search: Boolean, selected: Boolean, hovered: Boolean, modifier: Modifier) {
    Row(modifier.clip(RoundedCornerShape(50)).background(if (selected) HudTheme.accent else Color.White.copy(alpha = if (hovered) 0.2f else 0.08f)),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        val fg = if (selected) Color.Black else HudTheme.ink
        if (search) { HudIcon(Icons.Rounded.Search, 24f, fg); Spacer(Modifier.width(10.dp)) }
        BasicText(text, style = HudTheme.mont(18f, tracking = 2.5f, color = fg), maxLines = 1)
    }
}

@Composable
fun Thumbnail(video: YouTubeVideo, corner: Float, modifier: Modifier, badge: Float = 17f) {
    Box(modifier.clip(RoundedCornerShape(corner.dp))) {
        val hue = abs(video.id.hashCode() % 360).toFloat()
        Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color.hsv(hue, 0.35f, 0.32f), Color.hsv(hue, 0.4f, 0.12f)))))
        if (!video.id.startsWith("s") || video.id.length > 3) {
            AsyncImage(video.thumbnail, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
        if (video.duration.isNotEmpty()) {
            Box(Modifier.align(Alignment.BottomEnd).padding((badge * 0.47f).dp).height((badge * 1.65f).dp)
                .background(if (video.isLive) Color(0xFFE6403A) else Color.Black.copy(alpha = 0.8f), RoundedCornerShape((badge * 0.35f).dp))
                .padding(horizontal = (badge * 0.47f).dp), contentAlignment = Alignment.Center) {
                BasicText(video.duration, style = HudTheme.mont(badge, color = if (video.isLive) Color.Black else HudTheme.ink))
            }
        }
    }
}

@Composable
private fun VideoCard(video: YouTubeVideo, queued: Int?, playing: Boolean, hovered: Boolean, modifier: Modifier,
                      width: Float = YouTubeAppLayout.CARD_WIDTH) {
    Column(modifier.scale(if (hovered) 1.02f else 1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(width.dp, (width * YouTubeAppLayout.THUMB_HEIGHT / YouTubeAppLayout.CARD_WIDTH).dp)
            .border(4.dp, if (hovered) HudTheme.accent else Color.Transparent, RoundedCornerShape(18.dp))) {
            Thumbnail(video, 18f, Modifier.fillMaxSize())
            if (playing || queued != null) {
                Box(Modifier.padding(10.dp).height(26.dp).background(HudTheme.accent, RoundedCornerShape(50)).padding(horizontal = 10.dp),
                    contentAlignment = Alignment.Center) {
                    BasicText(if (playing) "PLAYING" else "QUEUED ${queued!! + 1}", style = HudTheme.mont(14f, tracking = 2f, color = Color.Black))
                }
            }
        }
        BasicText(video.title, style = HudTheme.mont(23f), maxLines = 2, overflow = TextOverflow.Ellipsis)
        BasicText(listOf(video.channel, video.meta).filter { it.isNotEmpty() }.joinToString(" · "),
            style = HudTheme.mont(17f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Watching: the video is the canvas, and only when paused do the title and time come up over it. */
@Composable
fun YouTubeFullscreen(y: HudSnapshot.YouTube, live: Boolean, standIn: Boolean) {
    Box(Modifier.size(HudTheme.CANVAS_WIDTH.dp, HudTheme.CANVAS_HEIGHT.dp).background(if (live) Color.Transparent else Color.Black)) {
        if (!live && standIn) StandInFrame(Modifier.fillMaxSize())
        if (y.notice.isNotEmpty()) {
            BasicText(y.notice, style = HudTheme.mont(30f, FontWeight.SemiBold, color = HudTheme.inkDim).copy(textAlign = TextAlign.Center),
                modifier = Modifier.align(Alignment.Center).padding(120.dp))
        } else if (y.hasVideo && !y.isPlaying && !y.isAd) {
            Column(Modifier.align(Alignment.BottomStart).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.9f))))
                .padding(start = 120.dp, end = 120.dp, top = 200.dp, bottom = 90.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                BasicText(y.channel.uppercase(), style = HudTheme.mont(20f, tracking = 4f, color = HudTheme.accent), maxLines = 1)
                BasicText(y.title, style = HudTheme.mont(52f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (!y.isLive) {
                    Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                        val t = HudTheme.mont(24f, color = HudTheme.inkDim)
                        BasicText(HudSnapshot.NowPlaying.time(y.elapsed), style = t)
                        ProgressLine(y.progress, Modifier.weight(1f).height(8.dp))
                        BasicText("−" + HudSnapshot.NowPlaying.time(maxOf(y.duration - y.elapsed, 0.0)), style = t)
                    }
                }
            }
        }
    }
}

/**
 * Watching in the centre: the video as large as the centre allows, with what it is and how far
 * along under it. The live video is the layer underneath; its place is cut out.
 */
@Composable
fun YouTubeCentreWatch(y: HudSnapshot.YouTube, live: Boolean, standIn: Boolean, size: Size) {
    val video = YouTubeAppLayout.centreVideo(size)
    val shape = RoundedCornerShape(HudTheme.CORNER.dp)
    Box(Modifier.fillMaxSize().hole(if (live && y.hasVideo) video else null, 16f)
        .clip(shape).background(HudTheme.surface).border(1.dp, HudTheme.edge, shape)) {
        if (!live) Box(Modifier.at(video).clip(RoundedCornerShape(16.dp)).background(Color.Black)) { if (standIn) StandInFrame(Modifier.fillMaxSize()) }
        Column(Modifier.at(Rect(Offset(video.left, video.bottom + 24), Size(video.width, size.height - video.bottom - 48))),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            BasicText(if (y.isAd) "AD" else if (y.isPlaying) "NOW PLAYING" else "PAUSED",
                style = HudTheme.mont(16f, tracking = 3f, color = if (y.isPlaying) HudTheme.accent else HudTheme.inkDim))
            BasicText(y.title, style = HudTheme.mont(32f), maxLines = 2, overflow = TextOverflow.Ellipsis)
            BasicText(y.channel, style = HudTheme.mont(22f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1)
            if (y.duration > 0) ProgressLine(y.progress, Modifier.padding(top = 6.dp).fillMaxWidth().height(6.dp))
        }
    }
}
