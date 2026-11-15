package com.thehud.desktop

import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaFormat
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import android.view.TextureView
import com.thehud.core.DesktopSource
import com.thehud.core.DesktopWindow
import com.thehud.core.HudSnapshot
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors

/** HudCast's framing, as the Mac speaks it: a kind byte, a big-endian length, the payload. */
object DesktopWire {
    const val SERVICE = "_thehud._tcp"
    const val WINDOWS = 1
    const val FORMAT = 2
    const val FRAME = 3
    const val SOURCE = 4
    const val COMMAND = 16
    const val MAX_PAYLOAD = 32 shl 20

    fun pack(kind: Int, payload: ByteArray): ByteArray {
        val out = ByteArray(5 + payload.size)
        out[0] = kind.toByte()
        val n = payload.size
        out[1] = (n ushr 24).toByte(); out[2] = (n ushr 16).toByte(); out[3] = (n ushr 8).toByte(); out[4] = n.toByte()
        System.arraycopy(payload, 0, out, 5, n)
        return out
    }

    /** SPS then PPS, each after a two-byte length. */
    fun parseFormat(data: ByteArray): Pair<ByteArray, ByteArray>? {
        val sets = mutableListOf<ByteArray>()
        var i = 0
        while (sets.size < 2 && i + 2 <= data.size) {
            val len = (data[i].toInt() and 0xFF shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
            if (i + len > data.size) return null
            sets += data.copyOfRange(i, i + len); i += len
        }
        return if (sets.size == 2) sets[0] to sets[1] else null
    }

    private val START = byteArrayOf(0, 0, 0, 1)

    /** Length-prefixed NAL units (AVCC) to start codes (Annex B), which MediaCodec reads. */
    fun annexB(avcc: ByteArray, from: Int = 0): ByteArray {
        val out = ByteArrayOutputStream(avcc.size + 16)
        var i = from
        while (i + 4 <= avcc.size) {
            val len = ((avcc[i].toInt() and 0xFF) shl 24) or ((avcc[i + 1].toInt() and 0xFF) shl 16) or
                ((avcc[i + 2].toInt() and 0xFF) shl 8) or (avcc[i + 3].toInt() and 0xFF)
            i += 4
            if (len <= 0 || i + len > avcc.size) break
            out.write(START); out.write(avcc, i, len); i += len
        }
        return out.toByteArray()
    }

    fun withStart(nal: ByteArray) = START + nal

    private val json = Json { encodeDefaults = false }

    /** Commands in the shape Swift's own encoding of the Mac's enum reads. */
    sealed interface Command {
        fun encode(): String
        data class Move(val x: Double, val y: Double) : Command {
            override fun encode() = buildJsonObject { putJsonObject("move") { put("x", x); put("y", y) } }.toString()
        }
        data class Click(val x: Double, val y: Double, val button: Int) : Command {
            override fun encode() = buildJsonObject { putJsonObject("click") { put("x", x); put("y", y); put("button", button) } }.toString()
        }
        data class Press(val x: Double, val y: Double) : Command {
            override fun encode() = buildJsonObject { putJsonObject("press") { put("x", x); put("y", y) } }.toString()
        }
        data class Release(val x: Double, val y: Double) : Command {
            override fun encode() = buildJsonObject { putJsonObject("release") { put("x", x); put("y", y) } }.toString()
        }
        data class Scroll(val x: Double, val y: Double, val dx: Double, val dy: Double) : Command {
            override fun encode() = buildJsonObject { putJsonObject("scroll") { put("x", x); put("y", y); put("dx", dx); put("dy", dy) } }.toString()
        }
        data class Text(val text: String) : Command {
            override fun encode() = buildJsonObject { putJsonObject("text") { put("_0", text) } }.toString()
        }
        data class Key(val key: String) : Command {
            override fun encode() = buildJsonObject { putJsonObject("key") { put("_0", key) } }.toString()
        }
        data class Select(val window: Long?) : Command {
            override fun encode() = buildJsonObject { putJsonObject("select") { window?.let { put("window", it) } } }.toString()
        }
    }

    fun windows(payload: ByteArray) = runCatching {
        Json { ignoreUnknownKeys = true }.decodeFromString(ListSerializer(DesktopWindow.serializer()), payload.decodeToString())
    }.getOrDefault(emptyList())

    fun source(payload: ByteArray) = runCatching {
        Json { ignoreUnknownKeys = true }.decodeFromString(DesktopSource.serializer(), payload.decodeToString())
    }.getOrNull()
}

/**
 * The phone's end of HudCast: finds the Mac on the network, takes its picture as H.264 and
 * decodes it onto the glasses, and sends the cursor, clicks and keys back. Never plays anything
 * on the Mac; it only shows the Mac's screen.
 */
class DesktopLink(private val context: Context, private val onChange: (HudSnapshot.Desktop) -> Unit) {
    private val tag = "DesktopLink"
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val sender = Executors.newSingleThreadExecutor()

    var state = HudSnapshot.Desktop()
        private set(value) { if (value != field) { field = value; onChange(value) } }

    private var active = false
    private var nsd: NsdManager? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private val services = mutableListOf<NsdServiceInfo>()
    private var socket: Socket? = null
    private var output: OutputStream? = null
    private var multicast: WifiManager.MulticastLock? = null
    private var generation = 0

    // The decoder lives with the surface; both are made and remade on the main thread's say.
    private var surface: Surface? = null
    private var codec: MediaCodec? = null
    private var sps: ByteArray? = null
    private var pps: ByteArray? = null
    private var waitingForKeyframe = true
    private val codecLock = Any()

    fun start() {
        if (active) return
        active = true
        multicast = context.getSystemService(WifiManager::class.java)?.createMulticastLock("thehud")?.apply {
            setReferenceCounted(false); runCatching { acquire() }
        }
        val manager = context.getSystemService(NsdManager::class.java) ?: return
        nsd = manager
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                main.post { state = state.copy(status = "CANNOT SEARCH THE NETWORK") }
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                main.post { if (services.none { it.serviceName == service.serviceName }) services += service; connectIfIdle() }
            }
            override fun onServiceLost(service: NsdServiceInfo) {
                main.post { services.removeAll { it.serviceName == service.serviceName } }
            }
        }
        discovery = listener
        runCatching { manager.discoverServices(DesktopWire.SERVICE, NsdManager.PROTOCOL_DNS_SD, listener) }
        state = state.copy(status = "LOOKING FOR YOUR MAC")
    }

    fun stop() {
        if (!active) return
        active = false
        discovery?.let { d -> runCatching { nsd?.stopServiceDiscovery(d) } }
        discovery = null
        services.clear()
        runCatching { multicast?.release() }
        generation++
        closeSocket()
        clear()
        state = state.copy(status = "LOOKING FOR YOUR MAC")
    }

    private fun clear() {
        state = state.copy(connected = false, hasPicture = false, source = null, windows = emptyList())
        synchronized(codecLock) { releaseCodec() }
    }

    private fun closeSocket() {
        runCatching { socket?.close() }
        socket = null; output = null
    }

    @Suppress("DEPRECATION")
    private fun connectIfIdle() {
        if (!active || socket != null) return
        val service = services.firstOrNull() ?: run { state = state.copy(status = "LOOKING FOR YOUR MAC"); return }
        val name = service.serviceName
        state = state.copy(status = "CONNECTING TO ${name.uppercase()}", host = name)
        val mine = ++generation
        socket = Socket()
        nsd?.resolveService(service, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) { main.post { if (mine == generation) dropped() } }
            override fun onServiceResolved(info: NsdServiceInfo) {
                io.execute { run(mine, info) }
            }
        })
    }

    @Suppress("DEPRECATION")
    private fun run(mine: Int, info: NsdServiceInfo) {
        val s = socket ?: return
        try {
            s.tcpNoDelay = true
            s.connect(InetSocketAddress(info.host, info.port), 5000)
            output = s.getOutputStream()
            main.post { if (mine == generation) state = state.copy(connected = true, status = "WAITING FOR ${state.host.uppercase()}") }
            val input = DataInputStream(s.getInputStream().buffered(256 * 1024))
            waitingForKeyframe = true
            while (mine == generation) {
                val kind = input.readUnsignedByte()
                val length = input.readInt()
                if (length < 0 || length > DesktopWire.MAX_PAYLOAD) break
                val payload = ByteArray(length)
                input.readFully(payload)
                handle(mine, kind, payload)
            }
        } catch (e: Exception) {
            Log.i(tag, "Link ended: ${e.message}")
        }
        main.post { if (mine == generation) dropped() }
    }

    private fun dropped() {
        closeSocket()
        clear()
        main.postDelayed({ connectIfIdle() }, 1500)
    }

    private fun handle(mine: Int, kind: Int, payload: ByteArray) {
        when (kind) {
            DesktopWire.WINDOWS -> DesktopWire.windows(payload).let { w -> main.post { if (mine == generation) state = state.copy(windows = w) } }
            DesktopWire.SOURCE -> DesktopWire.source(payload)?.let { src ->
                main.post { if (mine == generation) state = state.copy(source = src, host = src.host) }
                synchronized(codecLock) { if (codecSize != src.width to src.height) releaseCodec() }
            }
            DesktopWire.FORMAT -> DesktopWire.parseFormat(payload)?.let { (a, b) ->
                synchronized(codecLock) {
                    if (!a.contentEquals(sps) || !b.contentEquals(pps)) { sps = a; pps = b; releaseCodec() }
                }
            }
            DesktopWire.FRAME -> {
                if (payload.isEmpty()) return
                val key = payload[0].toInt() and 1 == 1
                synchronized(codecLock) {
                    if (waitingForKeyframe && !key) return
                    val c = codec ?: makeCodec() ?: return
                    waitingForKeyframe = false
                    val data = DesktopWire.annexB(payload, 1)
                    val index = runCatching { c.dequeueInputBuffer(20_000) }.getOrDefault(-1)
                    if (index < 0) return
                    c.getInputBuffer(index)?.apply { clear(); put(data) }
                    c.queueInputBuffer(index, 0, data.size, System.nanoTime() / 1000, if (key) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                    drain(c)
                }
                if (!state.hasPicture) main.post { if (mine == generation) state = state.copy(hasPicture = true) }
            }
        }
    }

    private var codecSize: Pair<Int, Int>? = null

    private fun makeCodec(): MediaCodec? {
        val out = surface ?: return null
        val a = sps ?: return null
        val b = pps ?: return null
        val w = state.source?.width ?: 1920
        val h = state.source?.height ?: 1200
        return runCatching {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
                setByteBuffer("csd-0", java.nio.ByteBuffer.wrap(DesktopWire.withStart(a)))
                setByteBuffer("csd-1", java.nio.ByteBuffer.wrap(DesktopWire.withStart(b)))
                setInteger(MediaFormat.KEY_PRIORITY, 0)
                setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).also {
                it.configure(format, out, null, 0)
                it.start()
                codec = it
                codecSize = w to h
            }
        }.onFailure { Log.w(tag, "No decoder", it) }.getOrNull()
    }

    private fun drain(c: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        while (true) {
            val i = runCatching { c.dequeueOutputBuffer(info, 0) }.getOrDefault(-1)
            if (i < 0) break
            // Shown at once: the newest frame is the only one worth seeing.
            c.releaseOutputBuffer(i, true)
        }
    }

    private fun releaseCodec() {
        codec?.let { runCatching { it.stop() }; runCatching { it.release() } }
        codec = null
        codecSize = null
        waitingForKeyframe = true
    }

    /** The glasses' picture of the Mac: a texture the decoder draws into. */
    fun attach(view: TextureView) {
        view.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                synchronized(codecLock) { releaseCodec(); surface?.release(); surface = Surface(texture) }
                // Ask for a keyframe by asking for the same source again.
                send(DesktopWire.Command.Select(state.source?.window))
            }
            override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {}
            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                synchronized(codecLock) { releaseCodec(); surface?.release(); surface = null }
                return true
            }
            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
        }
        view.surfaceTexture?.let { t -> view.surfaceTextureListener?.onSurfaceTextureAvailable(t, view.width, view.height) }
    }

    fun send(command: DesktopWire.Command) {
        val out = output ?: return
        if (!state.connected) return
        val bytes = DesktopWire.pack(DesktopWire.COMMAND, command.encode().encodeToByteArray())
        sender.execute { runCatching { out.write(bytes); out.flush() } }
    }
}
