package com.thehud.phone

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DirectionsCar
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MicOff
import androidx.compose.material.icons.rounded.MyLocation
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Replay10
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.thehud.HudController
import com.thehud.MusicAction
import com.thehud.PhoneAction
import com.thehud.RemotePhase
import com.thehud.RemoteZone
import com.thehud.SkyAction
import com.thehud.YouTubeAction
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme
import com.thehud.core.MapsLayout
import com.thehud.core.SkyLayer
import com.thehud.core.YouTubeVideo
import com.thehud.ui.HalftoneBackground
import kotlin.math.abs

// The phone's lower half for the apps that are better worked with a thumb than a cursor, and
// the remote, as PhonePads.swift has them.

private fun android.view.View.tick() = performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
private val pill = RoundedCornerShape(50)

@Composable
internal fun Card(modifier: Modifier, content: @Composable androidx.compose.foundation.layout.BoxScope.() -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Box(modifier.clip(shape).background(Color(0xFF171717)).border(1.dp, HudTheme.edge, shape)) { content() }
}

@Composable
internal fun Button(icon: ImageVector, title: String, modifier: Modifier, lit: Boolean = false, enabled: Boolean = true, action: () -> Unit) {
    val view = LocalView.current
    Column(modifier.fillMaxHeight().clip(RoundedCornerShape(16.dp)).background(if (lit) HudTheme.accent else Color(0xFF242424))
        .clickable(enabled = enabled) { view.tick(); action() },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        val fg = when { lit -> Color.Black; enabled -> HudTheme.ink; else -> HudTheme.inkFaint }
        Image(icon, null, Modifier.size(if (lit) 26.dp else 20.dp), colorFilter = ColorFilter.tint(fg))
        if (title.isNotEmpty()) {
            Spacer(Modifier.height(4.dp))
            BasicText(title, style = HudTheme.mont(9f, tracking = 1.6f, color = fg))
        }
    }
}

@Composable
private fun Caption(text: String, accent: Boolean = false) =
    BasicText(text, style = HudTheme.mont(9f, tracking = 2f, color = if (accent) HudTheme.accent else HudTheme.inkDim), maxLines = 1)

@Composable
private fun Chip(text: String, on: Boolean, modifier: Modifier = Modifier, action: () -> Unit) {
    val view = LocalView.current
    Box(modifier.height(28.dp).clip(pill).background(if (on) HudTheme.accent else Color(0xFF1F1F1F))
        .clickable { view.tick(); action() }.padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
        BasicText(text, style = HudTheme.mont(8.5f, tracking = 1f, color = if (on) Color.Black else HudTheme.inkDim), maxLines = 1)
    }
}

// ------------------------------------------------------------------ the remote

/**
 * Point the phone and the cursor follows: the big area clicks (held, it drags), the strip at the
 * side scrolls, the small button right-clicks, the bar at the foot puts the cursor back in the middle.
 */
@Composable
fun RemotePad(modifier: Modifier) {
    val c = HudController
    val view = LocalView.current
    fun zone(z: RemoteZone): Modifier = Modifier.pointerInput(z) {
        awaitEachGesture {
            awaitFirstDown()
            view.tick()
            c.perform(PhoneAction.Remote(z, RemotePhase.began))
            if (z == RemoteZone.scroll) {
                var last: Float? = null
                var carry = 0f
                while (true) {
                    val e = awaitPointerEvent()
                    val p = e.changes.firstOrNull() ?: break
                    if (!p.pressed) break
                    val y = p.position.y
                    last?.let { carry += y - it }
                    last = y
                    // A tick for every twenty points; down the strip scrolls down the page.
                    val step = 20 * density
                    while (abs(carry) >= step) {
                        val t = if (carry > 0) 1 else -1
                        carry -= t * step
                        c.remoteScroll(t)
                    }
                    p.consume()
                }
            } else {
                while (true) {
                    val e = awaitPointerEvent()
                    if (e.changes.none { it.pressed }) break
                }
            }
            c.perform(PhoneAction.Remote(z, RemotePhase.ended))
        }
    }
    Column(modifier.padding(horizontal = 12.dp).padding(top = 4.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Card(Modifier.weight(1f).fillMaxHeight().then(zone(RemoteZone.click))) {
                HalftoneBackground(Modifier.fillMaxSize())
                Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                    BasicText("CLICK", style = HudTheme.mont(14f, tracking = 3f))
                    BasicText("Point the phone · hold to drag", style = HudTheme.mont(11f, FontWeight.SemiBold, color = HudTheme.inkDim))
                }
            }
            Column(Modifier.width(74.dp).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Card(Modifier.weight(1f).fillMaxWidth().then(zone(RemoteZone.scroll))) {
                    BasicText("SCROLL", style = HudTheme.mont(9f, tracking = 2f, color = HudTheme.inkDim), modifier = Modifier.align(Alignment.Center))
                }
                Card(Modifier.height(74.dp).fillMaxWidth().then(zone(RemoteZone.rightClick))) {
                    BasicText("RIGHT", style = HudTheme.mont(9f, tracking = 2f, color = HudTheme.inkDim), modifier = Modifier.align(Alignment.Center))
                }
            }
        }
        Card(Modifier.height(62.dp).fillMaxWidth().then(zone(RemoteZone.centre))) {
            Row(Modifier.align(Alignment.Center), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Image(Icons.Rounded.MyLocation, null, Modifier.size(16.dp), colorFilter = ColorFilter.tint(HudTheme.ink))
                BasicText("CENTRE", style = HudTheme.mont(11f, tracking = 2.5f))
            }
        }
    }
}

// ------------------------------------------------------------------ the sky

@Composable
fun SkyControls() {
    val c = HudController
    val view = c.snapshot.skyView
    val hostView = LocalView.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Drag to look round and up, pinch to see more or less, double-tap to face ahead again.
        Card(Modifier.fillMaxWidth().weight(1f)
            .pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ ->
                    val fov = c.snapshot.skyView.fov
                    val perPoint = fov / 360.0 / density
                    if (pan.x != 0f || pan.y != 0f) c.perform(PhoneAction.Sky(SkyAction.Look(-pan.x * perPoint, pan.y * perPoint)))
                    if (zoom != 1f) c.perform(PhoneAction.Sky(SkyAction.Zoom(1.0 / zoom)))
                }
            }
            .pointerInput(Unit) { detectTapGestures(onDoubleTap = { hostView.tick(); c.perform(PhoneAction.Sky(SkyAction.Recentre)) }) }) {
            HalftoneBackground(Modifier.fillMaxSize())
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                BasicText("LOOK", style = HudTheme.mont(14f, tracking = 3f))
                BasicText(if (view.isAdjusted) "${view.fov.toInt()}° wide · double-tap to face ahead" else "Drag to look round · pinch to zoom",
                    style = HudTheme.mont(11f, FontWeight.SemiBold, color = HudTheme.inkDim))
            }
        }
        for (row in SkyLayer.entries.chunked(4)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (layer in row) Chip(layer.title, layer in view.layers, Modifier.weight(1f)) { c.perform(PhoneAction.Sky(SkyAction.Toggle(layer))) }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        Card(Modifier.fillMaxWidth().height(120.dp)) {
            val targets = c.skyTargets()
            if (targets.isEmpty()) BasicText("Nothing up yet", style = HudTheme.mont(12f, FontWeight.SemiBold, color = HudTheme.inkFaint),
                modifier = Modifier.align(Alignment.Center))
            LazyColumn(Modifier.fillMaxSize().padding(vertical = 6.dp)) {
                itemsIndexed(targets, key = { _, t -> t.id }) { _, t ->
                    val on = t.id == view.selected
                    Row(Modifier.fillMaxWidth().clickable { hostView.tick(); c.perform(PhoneAction.Sky(SkyAction.Select(t.id))) }
                        .background(if (on) HudTheme.accent.copy(alpha = 0.18f) else Color.Transparent).padding(horizontal = 14.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            BasicText(t.name, style = HudTheme.mont(13f, color = if (on) HudTheme.accent else HudTheme.ink), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            BasicText(t.kind.title, style = HudTheme.mont(8f, tracking = 1.5f, color = HudTheme.inkDim))
                        }
                        BasicText("${t.alt.toInt()}°", style = HudTheme.mont(12f, color = HudTheme.inkDim))
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ music

@Composable
fun MusicControls() {
    val c = HudController
    val music = c.snapshot.music
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Card(Modifier.fillMaxWidth().weight(1f)) {
            Row(Modifier.fillMaxSize().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(84.dp).clip(RoundedCornerShape(12.dp)).background(Color.White.copy(alpha = 0.07f))) {
                    c.artwork?.let { Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Caption(if (music == null) if (c.musicAllowed) "NOTHING PLAYING" else "ALLOW NOTIFICATION ACCESS IN SETTINGS"
                        else (music.app.ifEmpty { "NOW PLAYING" }).uppercase(), accent = music?.isPlaying == true)
                    BasicText(music?.title ?: "Play something on the phone", style = HudTheme.mont(16f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    music?.artist?.takeIf { it.isNotEmpty() }?.let {
                        BasicText(it, style = HudTheme.mont(12f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (music != null && music.duration > 0) {
                        Box(Modifier.padding(top = 6.dp).fillMaxWidth().height(4.dp).background(HudTheme.inkFaint, pill)) {
                            Box(Modifier.fillMaxWidth(music.progress).fillMaxHeight().background(HudTheme.ink, pill))
                        }
                        Row(Modifier.fillMaxWidth()) {
                            BasicText(HudSnapshot.NowPlaying.time(music.elapsed), style = HudTheme.mont(9f, color = HudTheme.inkDim))
                            Spacer(Modifier.weight(1f))
                            BasicText(HudSnapshot.NowPlaying.time(music.duration), style = HudTheme.mont(9f, color = HudTheme.inkDim))
                        }
                    }
                }
            }
        }
        Row(Modifier.height(64.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(Icons.Rounded.Replay10, "", Modifier.width(56.dp), enabled = music != null) { c.perform(PhoneAction.Music(MusicAction.Seek(-15.0))) }
            Button(Icons.Rounded.SkipPrevious, "", Modifier.weight(1f), enabled = music != null) { c.perform(PhoneAction.Music(MusicAction.Previous)) }
            Button(if (music?.isPlaying == true) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, "", Modifier.weight(1.3f), lit = true) {
                c.perform(PhoneAction.Music(MusicAction.PlayPause))
            }
            Button(Icons.Rounded.SkipNext, "", Modifier.weight(1f), enabled = music != null) { c.perform(PhoneAction.Music(MusicAction.Next)) }
            Button(Icons.Rounded.Forward10, "", Modifier.width(56.dp), enabled = music != null) { c.perform(PhoneAction.Music(MusicAction.Seek(15.0))) }
        }
    }
}

// ------------------------------------------------------------------ captions

@Composable
fun CaptionsControls() {
    val c = HudController
    val captions = c.snapshot.captions
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Card(Modifier.fillMaxWidth().weight(1f)) {
            Column(Modifier.fillMaxSize().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.Bottom)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Caption(if (c.captionsAllowed) captions.status else "ALLOW THE MICROPHONE IN SETTINGS", accent = captions.isListening)
                    Spacer(Modifier.weight(1f))
                    if (captions.isListening) BasicText(captions.elapsed, style = HudTheme.mont(10f, color = HudTheme.inkDim))
                }
                Spacer(Modifier.weight(1f))
                for (line in captions.lines.takeLast(3)) BasicText(line, style = HudTheme.mont(13f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 2)
                if (captions.partial.isNotEmpty()) BasicText(captions.partial, style = HudTheme.mont(13f, FontWeight.SemiBold, color = HudTheme.accent), maxLines = 2)
            }
        }
        Row(Modifier.height(64.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(if (captions.isListening) Icons.Rounded.MicOff else Icons.Rounded.Mic, if (captions.isListening) "STOP" else "LISTEN",
                Modifier.weight(1f), lit = true, enabled = c.captionsAllowed) { c.perform(PhoneAction.Captions) }
        }
    }
}

// ------------------------------------------------------------------ YouTube

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun YouTubeControls() {
    val c = HudController
    val y = c.snapshot.youtube
    val view = LocalView.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (tab in y.tabs) Chip(if (tab == HudSnapshot.YouTube.Tab.subscriptions) "SUBS" else tab.title,
                y.tab == tab && y.page == HudSnapshot.YouTube.Page.browse, Modifier.weight(1f)) {
                c.perform(PhoneAction.YouTube(if (tab == HudSnapshot.YouTube.Tab.search) YouTubeAction.Search else YouTubeAction.Tab(tab)))
            }
            Chip("WATCH", y.page == HudSnapshot.YouTube.Page.player, Modifier.weight(1f)) {
                c.perform(PhoneAction.YouTube(YouTubeAction.Page(if (y.page == HudSnapshot.YouTube.Page.player)
                    HudSnapshot.YouTube.Page.browse else HudSnapshot.YouTube.Page.player)))
            }
        }
        // While something plays: the queue and what comes next. Otherwise the tab's list. Tap plays, hold queues.
        val playing = y.hasVideo && y.page == HudSnapshot.YouTube.Page.player
        val list: List<Pair<YouTubeVideo, Int?>> = if (playing) y.queue.mapIndexed { i, v -> v to i } + y.upNext.filter { it.id != y.videoId }.map { it to null }
            else y.list(y.tab).map { it to null }
        Card(Modifier.fillMaxWidth().weight(1f)) {
            if (list.isEmpty()) BasicText(if (y.loading) "Loading…" else if (y.tab == HudSnapshot.YouTube.Tab.search) "Search for something" else
                y.problem.ifEmpty { "Nothing here yet" }, style = HudTheme.mont(12f, FontWeight.SemiBold, color = HudTheme.inkFaint),
                modifier = Modifier.align(Alignment.Center))
            LazyColumn(Modifier.fillMaxSize().padding(vertical = 4.dp)) {
                itemsIndexed(list, key = { i, (v, q) -> "${q ?: "n"}:${v.id}:$i" }) { _, (video, queued) ->
                    Row(Modifier.fillMaxWidth().combinedClickable(
                        onClick = { view.tick(); c.perform(PhoneAction.YouTube(queued?.let { YouTubeAction.PlayQueued(it) } ?: YouTubeAction.Play(video))) },
                        onLongClick = { view.tick(); c.perform(PhoneAction.YouTube(queued?.let { YouTubeAction.Dequeue(it) } ?: YouTubeAction.Enqueue(video))) })
                        .padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Box(Modifier.size(72.dp, 40.dp).clip(RoundedCornerShape(6.dp)).background(Color(0xFF222222))) {
                            if (!video.id.startsWith("s") || video.id.length > 2) AsyncImage(video.thumbnail, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                        }
                        Column(Modifier.weight(1f)) {
                            BasicText(video.title, style = HudTheme.mont(11f, FontWeight.SemiBold), maxLines = 2, overflow = TextOverflow.Ellipsis)
                            BasicText((if (queued != null) "QUEUED · " else "") + video.channel, style = HudTheme.mont(8.5f, tracking = 1f,
                                color = if (queued != null) HudTheme.accent else HudTheme.inkDim), maxLines = 1)
                        }
                    }
                }
            }
        }
        Row(Modifier.height(58.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (y.canSkipAd) Button(SkipNext, "SKIP AD", Modifier.weight(1f), lit = true) { c.perform(PhoneAction.YouTube(YouTubeAction.SkipAd)) }
            else {
                Button(Icons.Rounded.Replay10, "", Modifier.weight(1f), enabled = y.hasVideo && !y.isLive) { c.perform(PhoneAction.YouTube(YouTubeAction.Seek(-10.0))) }
                Button(if (y.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, "", Modifier.weight(1.3f), lit = true, enabled = y.hasVideo) {
                    c.perform(PhoneAction.YouTube(YouTubeAction.TogglePlay))
                }
                Button(Icons.Rounded.Forward10, "", Modifier.weight(1f), enabled = y.hasVideo && !y.isLive) { c.perform(PhoneAction.YouTube(YouTubeAction.Seek(10.0))) }
                Button(Icons.Rounded.SkipNext, "", Modifier.weight(1f), enabled = y.hasVideo) { c.perform(PhoneAction.YouTube(YouTubeAction.Next)) }
            }
        }
    }
}

private val SkipNext get() = Icons.Rounded.SkipNext

// ------------------------------------------------------------------ maps

@Composable
fun MapsControls() {
    val c = HudController
    val maps = c.snapshot.maps
    val view = LocalView.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Card(Modifier.fillMaxWidth().weight(1f)) {
            val nav = maps.navigation
            if (nav != null) Column(Modifier.fillMaxSize().padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Caption("TO " + nav.destination.uppercase(), accent = true)
                BasicText(if (nav.arrived) "Arrived" else nav.stepDistance, style = HudTheme.mont(28f))
                BasicText(nav.instruction, style = HudTheme.mont(13f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 2)
                Spacer(Modifier.weight(1f))
                BasicText("${nav.remainingTime} · ${nav.remainingDistance} · ARRIVE ${nav.arrival}", style = HudTheme.mont(10f, tracking = 1.5f, color = HudTheme.inkDim))
            } else if (maps.results.isEmpty()) {
                BasicText(maps.status ?: "Search for a place, then tap it for directions",
                    style = HudTheme.mont(12f, FontWeight.SemiBold, color = HudTheme.inkFaint), modifier = Modifier.align(Alignment.Center).padding(16.dp))
            } else LazyColumn(Modifier.fillMaxSize().padding(vertical = 4.dp)) {
                itemsIndexed(maps.results) { i, place ->
                    Row(Modifier.fillMaxWidth().clickable { view.tick(); c.perform(PhoneAction.Maps(MapsLayout.Target.result, i)) }
                        .padding(horizontal = 14.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            BasicText(place.name, style = HudTheme.mont(13f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            BasicText(place.detail, style = HudTheme.mont(9f, FontWeight.SemiBold, color = HudTheme.inkDim), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        BasicText(place.distance, style = HudTheme.mont(11f, color = HudTheme.inkDim))
                    }
                }
            }
        }
        Row(Modifier.height(64.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(Icons.Rounded.Remove, "", Modifier.width(56.dp)) { c.perform(PhoneAction.Maps(MapsLayout.Target.zoomOut)) }
            if (maps.navigation != null) {
                Button(if (maps.driving) Icons.Rounded.DirectionsCar else Icons.Rounded.DirectionsWalk, if (maps.driving) "DRIVE" else "WALK",
                    Modifier.weight(1f)) { c.perform(PhoneAction.Maps(MapsLayout.Target.transport)) }
                Button(Icons.Rounded.Close, "END", Modifier.weight(1f), lit = true) { c.perform(PhoneAction.Maps(MapsLayout.Target.endRoute)) }
            } else Button(Icons.Rounded.Search, if (maps.isEditing) "DONE" else "SEARCH", Modifier.weight(1f), lit = true) {
                c.perform(PhoneAction.Maps(MapsLayout.Target.search))
            }
            Button(Icons.Rounded.Add, "", Modifier.width(56.dp)) { c.perform(PhoneAction.Maps(MapsLayout.Target.zoomIn)) }
        }
    }
}

