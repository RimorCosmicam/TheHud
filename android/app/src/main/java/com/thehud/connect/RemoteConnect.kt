package com.thehud.connect

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import com.thehud.HudController
import com.thehud.desktop.DesktopWire
import com.thehud.desktop.StreamDecoder
import java.io.DataInputStream
import com.thehud.MusicAction
import com.thehud.NoteAction
import com.thehud.PhoneAction
import com.thehud.PhotosAction
import com.thehud.PrompterAction
import com.thehud.SkyAction
import com.thehud.TimerAction
import com.thehud.YouTubeAction
import com.thehud.core.HudArrangement
import com.thehud.core.HudEdge
import com.thehud.core.HudPanelKind
import com.thehud.core.HudSide
import com.thehud.core.HudSnapshot
import com.thehud.core.HudSpot
import com.thehud.core.SkyLayer
import com.thehud.core.YouTubeVideo
import com.thehud.touchpad.GestureEvent
import kotlinx.serialization.json.Json
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedWriter
import java.net.Inet4Address
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.concurrent.thread

/**
 * Remote Connect: the iPhone app working this phone's glasses over the local network.
 *
 * One line of JSON per message over TCP. The phone that drives the glasses listens and shows a QR
 * code holding its id, its address and a secret key; the iPhone proves it has the key by
 * answering a random challenge with an HMAC, and from then on sends what its own screen would have
 * done (actions, touchpad gestures, typing) and gets this phone's state back to draw. The service
 * is also on DNS-SD as `_thehud-remote._tcp` (HudCast has `_thehud._tcp`), named by the id, so a paired iPhone finds it again when the
 * address changes.
 */
class RemoteServer(private val context: Context) {
    /** A message from the paired iPhone, on the main thread. */
    var onMessage: ((JSONObject) -> Unit)? = null
    /** The paired iPhone came (its name, and whether it hosts) or went (null), on the main thread. */
    var onPeer: ((String?, Boolean) -> Unit)? = null
    /** Host mode: the iPhone's own glasses picture, decoded onto this phone's glasses. */
    val hostPicture = StreamDecoder("RemoteHost") { send(JSONObject().put("t", "keyframe").toString()) }

    private val prefs = context.getSharedPreferences("connect", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private val out = Executors.newSingleThreadExecutor()
    private val random = SecureRandom()
    @Volatile private var server: ServerSocket? = null
    @Volatile private var client: Socket? = null
    @Volatile private var writer: BufferedWriter? = null
    private var registration: NsdManager.RegistrationListener? = null

    val id: String = prefs.getString("id", null) ?: ByteArray(4).also(random::nextBytes)
        .joinToString("") { "%02x".format(it) }.also { prefs.edit().putString("id", it).apply() }
    private var key: ByteArray = prefs.getString("key", null)?.let { Base64.decode(it, Base64.NO_WRAP) } ?: newKeyBytes()
    var port = 0
        private set

    private fun newKeyBytes(): ByteArray = ByteArray(32).also {
        random.nextBytes(it)
        prefs.edit().putString("key", Base64.encodeToString(it, Base64.NO_WRAP)).apply()
    }

    fun start() {
        if (server != null) return
        thread(name = "remote-connect", isDaemon = true) {
            val socket = runCatching { ServerSocket(PORT) }.getOrNull() ?: runCatching { ServerSocket(0) }.getOrNull()
                ?: return@thread
            server = socket
            port = socket.localPort
            main.post { advertise() }
            while (!socket.isClosed) {
                val s = runCatching { socket.accept() }.getOrNull() ?: break
                thread(name = "remote-connect-peer", isDaemon = true) { serve(s) }
            }
        }
    }

    /** What the QR code says. The address is a first guess; DNS-SD finds the phone after that. */
    fun pairingLink(): String {
        val k = Base64.encodeToString(key, Base64.NO_WRAP or Base64.URL_SAFE or Base64.NO_PADDING)
        return "thehud://connect?id=$id&k=$k&h=${wifiAddress() ?: ""}&p=$port"
    }

    /** A new key: the paired iPhone has to scan again. */
    fun forget() {
        key = newKeyBytes()
        drop()
    }

    fun drop() {
        runCatching { client?.close() }
    }

    val hasNetwork: Boolean get() = wifiAddress() != null

    /** One line to the paired iPhone, if there is one. */
    fun send(line: String) {
        val w = writer ?: return
        out.execute {
            runCatching { w.write(line); w.write("\n"); w.flush() }.onFailure { runCatching { client?.close() } }
        }
    }

    private fun serve(s: Socket) {
        val previous = client
        try {
            s.tcpNoDelay = true
            s.keepAlive = true
            s.soTimeout = 10_000
            val input = s.getInputStream().bufferedReader()
            val w = s.getOutputStream().bufferedWriter()
            val nonce = ByteArray(16).also(random::nextBytes)
            w.write(JSONObject().put("t", "hello").put("v", 1).put("id", id).put("name", Build.MODEL)
                .put("nonce", Base64.encodeToString(nonce, Base64.NO_WRAP)).toString())
            w.write("\n"); w.flush()
            val auth = JSONObject(input.readLine() ?: return)
            val expected = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }.doFinal(nonce)
            val given = runCatching { Base64.decode(auth.optString("mac"), Base64.NO_WRAP) }.getOrNull() ?: ByteArray(0)
            if (auth.optString("t") != "auth" || !MessageDigest.isEqual(expected, given)) {
                Log.w(TAG, "a phone without the key tried to connect")
                return
            }
            // One iPhone at a time: the newest wins.
            runCatching { previous?.close() }
            s.soTimeout = 0
            client = s
            writer = w
            val name = auth.optString("name").ifEmpty { "iPhone" }
            val hosting = auth.optString("mode") == "host"
            main.post { onPeer?.invoke(name, hosting) }
            send(JSONObject().put("t", "welcome").toString())
            if (hosting) {
                // From here the iPhone sends its picture, framed as HudCast frames its Mac's. It waited
                // for the welcome, so nothing of it is in the line reader's buffer.
                hostPicture.reset()
                val video = DataInputStream(s.getInputStream().buffered(256 * 1024))
                while (true) {
                    val kind = video.readUnsignedByte()
                    val length = video.readInt()
                    if (length < 0 || length > DesktopWire.MAX_PAYLOAD) break
                    val payload = ByteArray(length)
                    video.readFully(payload)
                    when (kind) {
                        DesktopWire.FORMAT -> hostPicture.format(payload)
                        DesktopWire.FRAME -> hostPicture.frame(payload)
                        DesktopWire.SOURCE -> DesktopWire.source(payload)?.let { hostPicture.size(it.width, it.height) }
                    }
                }
            } else while (true) {
                val line = input.readLine() ?: break
                val message = runCatching { JSONObject(line) }.getOrNull() ?: continue
                main.post { onMessage?.invoke(message) }
            }
        } catch (e: Exception) {
            Log.i(TAG, "connection ended: ${e.message}")
        } finally {
            runCatching { s.close() }
            if (client === s) {
                client = null
                writer = null
                hostPicture.reset()
                main.post { onPeer?.invoke(null, false) }
            }
        }
    }

    private fun advertise() {
        val nsd = context.getSystemService(NsdManager::class.java) ?: return
        val info = NsdServiceInfo().apply {
            serviceName = "TheHud-$id"
            serviceType = SERVICE
            port = this@RemoteServer.port
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {}
            override fun onRegistrationFailed(info: NsdServiceInfo, code: Int) { Log.w(TAG, "DNS-SD failed: $code") }
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, code: Int) {}
        }
        registration = listener
        runCatching { nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener) }
    }

    /** The phone's address on Wi-Fi (or Ethernet): where the iPhone, on the same network, can reach it. */
    private fun wifiAddress(): String? {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return null
        @Suppress("DEPRECATION")
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) && !caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) continue
            val address = cm.getLinkProperties(network)?.linkAddresses?.map { it.address }
                ?.firstOrNull { it is Inet4Address && !it.isLoopbackAddress }
            if (address != null) return address.hostAddress
        }
        return null
    }

    companion object {
        const val PORT = 47825
        const val SERVICE = "_thehud-remote._tcp."
        private const val TAG = "RemoteConnect"
    }
}

/** The messages, both ways: what the iPhone's screen did, and this phone's state for it to draw. */
object RemoteWire {
    private val json = Json { encodeDefaults = true }

    private fun kind(o: JSONObject, name: String = "kind"): HudPanelKind? =
        HudPanelKind.entries.firstOrNull { it.name == o.optString(name) }

    private fun spot(s: String): HudSpot? = when {
        s == "middle" -> HudSpot.Middle
        s == "off" -> HudSpot.Off
        s.startsWith("row:") -> s.removePrefix("row:").toIntOrNull()?.let { HudSpot.Row(it) }
        s.startsWith("left:") -> s.removePrefix("left:").toIntOrNull()?.let { HudSpot.Slot(HudSide.left, it) }
        s.startsWith("right:") -> s.removePrefix("right:").toIntOrNull()?.let { HudSpot.Slot(HudSide.right, it) }
        else -> null
    }

    private fun video(o: JSONObject?): YouTubeVideo? = o?.let {
        YouTubeVideo(it.optString("id"), it.optString("title"), it.optString("channel"), it.optString("duration"), it.optString("meta"))
    }

    /** An action from the iPhone, as this phone's own; null for what it has no such thing for. */
    fun action(o: JSONObject, c: HudController): PhoneAction? = when (o.optString("a")) {
        "back" -> PhoneAction.Back
        "forward" -> PhoneAction.Forward
        "reload" -> PhoneAction.Reload
        "home" -> PhoneAction.Home
        "favorite" -> PhoneAction.Favorite
        "address" -> PhoneAction.Address
        "keyboard" -> PhoneAction.Keyboard
        "newTab" -> PhoneAction.NewTab
        "clearView" -> PhoneAction.ClearView
        "selectTab" -> PhoneAction.SelectTab(o.optInt("i"))
        "closeTab" -> PhoneAction.CloseTab(o.optInt("i"))
        "tapPanel" -> kind(o)?.let { PhoneAction.TapPanel(it) }
        "solo" -> kind(o)?.let { PhoneAction.Solo(it) }
        // The APP picker: any app in the centre, as on the iPhone.
        "centre" -> kind(o)?.let { PhoneAction.Centre(it) }
        "prompter" -> when (o.optString("c")) {
            "toggle" -> PrompterAction.Toggle
            "faster" -> PrompterAction.Faster
            "slower" -> PrompterAction.Slower
            "restart" -> PrompterAction.Restart
            else -> null
        }?.let { PhoneAction.Prompter(it) }
        "photos" -> when (o.optString("c")) {
            "step" -> PhoneAction.Photos(PhotosAction.Step(o.optInt("by", 1)))
            "open" -> PhoneAction.Photos(PhotosAction.Open)
            else -> null
        }
        "place" -> kind(o)?.let { k -> spot(o.optString("spot"))?.let { PhoneAction.Place(k, it) } }
        "scene" -> PhoneAction.Scene(o.optInt("i"))
        "resetScene" -> PhoneAction.ResetScene(o.optInt("i"))
        "layout" -> PhoneAction.Layout(HudEdge.entries.firstOrNull { it.name == o.optString("edge") })
        "macWindow" -> {
            val i = o.optInt("i", -1)
            PhoneAction.MacWindow(c.snapshot.desktop.windows.getOrNull(i)?.id)
        }
        "music" -> when (o.optString("c")) {
            "previous" -> PhoneAction.Music(MusicAction.Previous)
            "next" -> PhoneAction.Music(MusicAction.Next)
            "playPause" -> PhoneAction.Music(MusicAction.PlayPause)
            else -> null
        }
        "timer" -> when (o.optString("c")) {
            "toggle" -> PhoneAction.Timer(TimerAction.Toggle)
            "reset" -> PhoneAction.Timer(TimerAction.Reset)
            "set" -> PhoneAction.Timer(TimerAction.Set(o.optInt("m")))
            "add" -> PhoneAction.Timer(TimerAction.Add(o.optInt("m")))
            else -> null
        }
        "note" -> when (o.optString("c")) {
            "write" -> PhoneAction.Note(NoteAction.Write)
            "clear" -> PhoneAction.Note(NoteAction.Clear)
            "scroll" -> PhoneAction.Note(NoteAction.Scroll(o.optDouble("by", 0.0).toFloat()))
            else -> null
        }
        "captions" -> PhoneAction.Captions
        "sky" -> when (o.optString("c")) {
            "look" -> PhoneAction.Sky(SkyAction.Look(o.optDouble("pan", 0.0), o.optDouble("tilt", 0.0)))
            "zoom" -> PhoneAction.Sky(SkyAction.Zoom(o.optDouble("f", 1.0)))
            "recentre" -> PhoneAction.Sky(SkyAction.Recentre)
            "toggle" -> SkyLayer.entries.firstOrNull { it.name == o.optString("layer") }?.let { PhoneAction.Sky(SkyAction.Toggle(it)) }
            "select" -> PhoneAction.Sky(SkyAction.Select(o.optString("id").ifEmpty { null }))
            else -> null
        }
        "youtube" -> when (o.optString("c")) {
            "togglePlay" -> YouTubeAction.TogglePlay
            "next" -> YouTubeAction.Next
            "skipAd" -> YouTubeAction.SkipAd
            "seek" -> YouTubeAction.Seek(o.optDouble("by", 0.0))
            "search" -> YouTubeAction.Search
            "play" -> video(o.optJSONObject("video"))?.let { YouTubeAction.Play(it) }
            "playQueued" -> YouTubeAction.PlayQueued(o.optInt("i"))
            "enqueue" -> video(o.optJSONObject("video"))?.let { YouTubeAction.Enqueue(it) }
            "dequeue" -> YouTubeAction.Dequeue(o.optInt("i"))
            "page" -> HudSnapshot.YouTube.Page.entries.firstOrNull { it.name == o.optString("page") }?.let { YouTubeAction.Page(it) }
            "tab" -> HudSnapshot.YouTube.Tab.entries.firstOrNull { it.name == o.optString("tab") }?.let { YouTubeAction.Tab(it) }
            else -> null
        }?.let { PhoneAction.YouTube(it) }
        else -> null
    }

    fun gesture(o: JSONObject): GestureEvent? = when (o.optString("g")) {
        "move" -> GestureEvent.Move(o.optInt("dx"), o.optInt("dy"), o.optBoolean("drag"))
        "click" -> GestureEvent.Click(o.optInt("button", 1).toByte(), o.optBoolean("down"))
        "scroll" -> GestureEvent.Scroll(o.optInt("v"), o.optInt("h"))
        "fling" -> GestureEvent.ScrollFling(o.optDouble("vx", 0.0).toFloat(), o.optDouble("vy", 0.0).toFloat())
        "pinch" -> GestureEvent.Pinch(o.optDouble("s", 1.0).toFloat())
        "tap" -> GestureEvent.TapClick
        "right" -> GestureEvent.RightClick
        "dragStart" -> GestureEvent.DoubleTapDragStart
        "dragEnd" -> GestureEvent.DragEnd
        else -> null
    }

    private fun videos(list: List<YouTubeVideo>) = JSONArray().also { a ->
        list.forEach { a.put(JSONObject().put("id", it.id).put("title", it.title).put("channel", it.channel)
            .put("duration", it.duration).put("meta", it.meta)) }
    }

    /** Everything the iPhone draws of this phone. */
    fun state(c: HudController): String {
        val s = c.snapshot
        val o = JSONObject().put("t", "state")
        o.put("arrangement", JSONObject(json.encodeToString(HudArrangement.serializer(), c.arrangement)))
        o.put("solo", c.solo?.name ?: JSONObject.NULL)
        o.put("clearView", c.clearView)
        o.put("scene", c.sceneIndex)
        o.put("scenes", JSONArray(c.scenes.map { it.name }))
        o.put("glasses", c.glassesConnected)
        o.put("keyboard", c.keyboardTarget?.name ?: JSONObject.NULL)
        o.put("draft", c.draft)
        val b = s.browser
        o.put("browser", JSONObject().put("tabs", JSONArray(b.tabs)).put("activeTab", b.activeTab)
            .put("canGoBack", b.canGoBack).put("canGoForward", b.canGoForward).put("isHome", b.isHome)
            .put("isFavorite", b.isFavorite).put("url", b.url).put("title", b.title))
        s.music?.let { m ->
            o.put("music", JSONObject().put("title", m.title).put("artist", m.artist).put("album", m.album)
                .put("isPlaying", m.isPlaying).put("elapsed", m.elapsed).put("duration", m.duration))
        }
        val t = s.timer
        o.put("timer", JSONObject().put("text", t.text).put("progress", t.progress?.toDouble() ?: JSONObject.NULL)
            .put("state", t.state.name).put("isStopwatch", t.isStopwatch))
        o.put("note", JSONObject().put("text", s.note.text).put("isEditing", s.note.isEditing))
        val cap = s.captions
        o.put("captions", JSONObject().put("isListening", cap.isListening).put("lines", JSONArray(cap.lines))
            .put("partial", cap.partial).put("status", cap.status).put("elapsed", cap.elapsed))
        val y = s.youtube
        o.put("youtube", JSONObject().put("hasVideo", y.hasVideo).put("videoId", y.videoId).put("title", y.title)
            .put("channel", y.channel).put("isPlaying", y.isPlaying).put("isLive", y.isLive).put("elapsed", y.elapsed)
            .put("duration", y.duration).put("isAd", y.isAd).put("canSkipAd", y.canSkipAd).put("notice", y.notice)
            .put("page", y.page.name).put("tab", y.tab.name).put("showsSubscriptions", y.showsSubscriptions)
            .put("query", y.query).put("isEditingQuery", y.isEditingQuery).put("home", videos(y.home))
            .put("subscriptions", videos(y.subscriptions)).put("results", videos(y.results))
            .put("upNext", videos(y.upNext)).put("queue", videos(y.queue)))
        val p = s.photos
        o.put("photos", JSONObject().put("hasAccess", p.hasAccess).put("count", p.count).put("current", p.current)
            .put("selected", p.selected).put("scrollRow", p.scrollRow).put("viewing", p.viewing).put("caption", p.caption))
        o.put("prompter", JSONObject().put("isRunning", s.prompter.isRunning).put("speed", s.prompter.speed))
        return o.toString()
    }
}
