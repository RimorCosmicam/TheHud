package com.thehud.youtube

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.thehud.core.YouTubeVideo
import com.thehud.web.WebTab
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale

/**
 * Reads YouTube's pages for the lists the app shows, as on the iPhone: every page carries its
 * content as one JSON object, `ytInitialData`, and videos are looked for anywhere in it, in the
 * older `videoRenderer` shapes and the newer `lockupViewModel`. Shorts, playlists and ads are left out.
 */
object YouTubeData {
    fun videos(html: String): List<YouTubeVideo> = initialData(html)?.let(::videos) ?: emptyList()

    fun initialData(html: String): Any? {
        for (marker in listOf("var ytInitialData = ", "window[\"ytInitialData\"] = ", "ytInitialData = ")) {
            val start = html.indexOf(marker).takeIf { it >= 0 } ?: continue
            val from = start + marker.length
            val end = html.indexOf(";</script>", from).takeIf { it >= 0 } ?: continue
            runCatching { JSONTokener(html.substring(from, end)).nextValue() }.getOrNull()?.let { return it }
        }
        return null
    }

    fun videos(data: Any): List<YouTubeVideo> {
        val found = mutableListOf<YouTubeVideo>()
        val seen = mutableSetOf<String>()
        walk(data) { key, value ->
            val video = when (key) {
                "videoRenderer", "gridVideoRenderer", "compactVideoRenderer" -> renderer(value)
                "lockupViewModel" -> lockup(value)
                else -> return@walk false
            }
            if (video != null && seen.add(video.id)) found += video
            true
        }
        return found
    }

    private fun renderer(value: Any): YouTubeVideo? {
        val r = value as? JSONObject ?: return null
        val id = r.optString("videoId").ifEmpty { return null }
        val url = dig(r, "navigationEndpoint", "commandMetadata", "webCommandMetadata", "url") as? String ?: ""
        if (url.contains("/shorts/")) return null
        val title = text(r.opt("title")).ifEmpty { return null }
        val channel = listOf("ownerText", "shortBylineText", "longBylineText").map { text(r.opt(it)) }.firstOrNull { it.isNotEmpty() } ?: ""
        var duration = text(r.opt("lengthText"))
        if (duration.isEmpty()) r.optJSONArray("thumbnailOverlays")?.let { o ->
            duration = (0 until o.length()).mapNotNull { o.optJSONObject(it)?.optJSONObject("thumbnailOverlayTimeStatusRenderer") }
                .map { text(it.opt("text")) }.firstOrNull { it.isNotEmpty() } ?: ""
        }
        if (duration.isEmpty()) r.optJSONArray("badges")?.let { b ->
            if ((0 until b.length()).any { text(b.optJSONObject(it)?.optJSONObject("metadataBadgeRenderer")?.opt("label")).uppercase() == "LIVE" }) duration = "LIVE"
        }
        val views = listOf("shortViewCountText", "viewCountText").map { text(r.opt(it)) }.firstOrNull { it.isNotEmpty() } ?: ""
        val meta = listOf(views, text(r.opt("publishedTimeText"))).filter { it.isNotEmpty() }.joinToString(" · ")
        return YouTubeVideo(id, title, channel, if (duration.uppercase() == "LIVE") "LIVE" else duration, meta)
    }

    private fun lockup(value: Any): YouTubeVideo? {
        val l = value as? JSONObject ?: return null
        if (l.optString("contentType") != "LOCKUP_CONTENT_TYPE_VIDEO") return null
        val id = l.optString("contentId").ifEmpty { return null }
        val metadata = l.optJSONObject("metadata")?.optJSONObject("lockupMetadataViewModel") ?: return null
        val title = text(metadata.opt("title")).ifEmpty { return null }
        val rowsJson = dig(metadata, "metadata", "contentMetadataViewModel", "metadataRows") as? JSONArray
        val rows = (0 until (rowsJson?.length() ?: 0)).mapNotNull { i ->
            val parts = rowsJson!!.optJSONObject(i)?.optJSONArray("metadataParts") ?: return@mapNotNull null
            (0 until parts.length()).map { text(parts.optJSONObject(it)?.opt("text")) }.filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }
        }
        var duration = ""
        l.opt("contentImage")?.let { image ->
            walk(image) { key, v ->
                if (key != "thumbnailBadgeViewModel" || duration.isNotEmpty()) return@walk false
                val badge = text((v as? JSONObject)?.opt("text"))
                // "New" and the like are labels, not lengths.
                if (badge.contains(":") || badge.uppercase() == "LIVE") duration = badge
                true
            }
        }
        return YouTubeVideo(id, title, rows.firstOrNull()?.firstOrNull() ?: "",
            if (duration.uppercase() == "LIVE") "LIVE" else duration, rows.drop(1).firstOrNull()?.joinToString(" · ") ?: "")
    }

    private fun dig(value: Any?, vararg keys: String): Any? = keys.fold(value) { v, k -> (v as? JSONObject)?.opt(k) }

    /** YouTube's text comes as `simpleText`, as `runs` to join, or as `content`. */
    fun text(value: Any?): String {
        if (value is String) return value
        val d = value as? JSONObject ?: return ""
        d.optString("simpleText").takeIf { d.has("simpleText") }?.let { return it }
        d.optString("content").takeIf { d.has("content") }?.let { return it }
        val runs = d.optJSONArray("runs") ?: return ""
        return (0 until runs.length()).joinToString("") { runs.optJSONObject(it)?.optString("text") ?: "" }
    }

    /** Every key in the tree, depth first; `visit` returns true when it took the value. */
    private fun walk(value: Any, visit: (String, Any) -> Boolean) {
        when (value) {
            is JSONObject -> for (key in value.keys()) {
                val child = value.opt(key) ?: continue
                if (!visit(key, child)) walk(child, visit)
            }
            is JSONArray -> for (i in 0 until value.length()) value.opt(i)?.let { walk(it, visit) }
        }
    }

    // ------------------------------------------------------------------ lists

    const val HOME = "https://www.youtube.com/"
    const val SUBSCRIPTIONS = "https://www.youtube.com/feed/subscriptions"

    /** "sp" asks for videos only: no channels, playlists or Shorts shelves. */
    fun searchUrl(query: String) = "https://www.youtube.com/results?search_query=" + URLEncoder.encode(query, "UTF-8") + "&sp=EgIQAQ%3D%3D"

    /** Whether someone is signed in to YouTube in the app's web views. */
    val isSignedIn get() = CookieManager.getInstance().getCookie("https://www.youtube.com")?.let {
        it.contains("SAPISID=") || it.contains("__Secure-3PSID=") || it.contains("LOGIN_INFO=")
    } ?: false

    /** A page's videos, fetched as the signed-in wearer. Null when YouTube could not be reached. */
    suspend fun fetch(at: String): List<YouTubeVideo>? = withContext(Dispatchers.IO) {
        val cookies = withContext(Dispatchers.Main) { CookieManager.getInstance().getCookie("https://www.youtube.com") }
        runCatching {
            val c = URL(at).openConnection() as HttpURLConnection
            c.connectTimeout = 20_000; c.readTimeout = 20_000
            if (!cookies.isNullOrEmpty()) c.setRequestProperty("Cookie", cookies)
            c.setRequestProperty("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15")
            c.setRequestProperty("Accept-Language", Locale.getDefault().toLanguageTag() + ",en;q=0.8")
            val html = c.inputStream.bufferedReader().use { it.readText() }
            videos(html)
        }.getOrNull()
    }
}

/**
 * YouTube's own player and nothing else of its page: a web view of its own, apart from the
 * browser's tabs, loading the ordinary watch page with the app's cookies, so whoever is signed in
 * in the browser is signed in here. A style sheet put in before the page draws hides all but the
 * player; the HUD draws its own titles, buttons and lists around it.
 */
/**
 * A context at one pixel a CSS pixel. The glasses report no density of their own, so a web view
 * there took the phone's (2.625), and Chromium drew the video's picture at its size in CSS pixels:
 * 1280 pixels of page, 488 pixels of picture, in the top left corner. At one to one the two agree.
 */
private fun onePixelAPoint(context: Context): Context {
    val config = android.content.res.Configuration(context.resources.configuration)
    config.densityDpi = android.util.DisplayMetrics.DENSITY_DEFAULT
    return context.createConfigurationContext(config)
}

@SuppressLint("SetJavaScriptEnabled")
class YouTubePlayer(context: Context, private val onChange: (State) -> Unit) {
    data class State(
        val hasVideo: Boolean = false, val videoId: String = "", val title: String = "", val channel: String = "",
        val isPlaying: Boolean = false, val ended: Boolean = false, val elapsed: Double = 0.0, val duration: Double = 0.0,
        val isAd: Boolean = false, val canSkipAd: Boolean = false, val notice: String = "",
    )

    var state = State()
        private set
    private val main = Handler(Looper.getMainLooper())
    private var loadedId = ""
    private var loadedAt = 0L
    private var loading = false
    private var polling = false

    val view: WebView = WebView(onePixelAPoint(context)).apply {
        setBackgroundColor(Color.BLACK)
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.mediaPlaybackRequiresUserGesture = false
        WebTab.desktop(this)
        isFocusable = false
        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
        val early = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        if (early) runCatching { WebViewCompat.addDocumentStartJavaScript(this, PLAYER_ONLY, setOf("https://www.youtube.com")) }
        webViewClient = object : WebViewClient() {
            // Never hand youtube.com to the YouTube app, or anything to anything else.
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val scheme = request.url.scheme ?: return true
                return scheme !in setOf("http", "https", "about", "blob", "data")
            }
            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                loading = true
                if (!early) view.evaluateJavascript(PLAYER_ONLY, null)
            }
            override fun onPageFinished(view: WebView, url: String?) {
                loading = false
                view.evaluateJavascript(PLAYER_ONLY, null)
            }
        }
    }

    fun detach() { (view.parent as? ViewGroup)?.removeView(view) }

    /**
     * Just put into a new place (another window, or out of Host mode's view and back): the page
     * follows its new size, but Chromium can keep the video's own picture at the size it had,
     * playing small in the top left corner. A one-pixel nudge of the view's size, and resize events
     * in the page, make it lay the picture out again.
     */
    fun settle() {
        val params = view.layoutParams as? android.widget.FrameLayout.LayoutParams ?: return
        for (delay in longArrayOf(0, 250, 1200)) main.postDelayed({
            if (view.parent == null) return@postDelayed
            params.rightMargin = 1
            view.layoutParams = params
            main.postDelayed({
                params.rightMargin = 0
                view.layoutParams = params
                view.evaluateJavascript("window.dispatchEvent(new Event('resize'))", null)
            }, 60)
        }, delay)
    }

    fun play(id: String) {
        loadedId = id
        loadedAt = System.currentTimeMillis()
        state = State(hasVideo = true, videoId = id)
        onChange(state)
        view.loadUrl("https://www.youtube.com/watch?v=$id")
        if (!polling) { polling = true; main.postDelayed(::poll, 1000) }
    }

    /** Stops and lets the page go, so nothing plays unseen. */
    fun stop() {
        polling = false
        main.removeCallbacksAndMessages(null)
        view.evaluateJavascript("document.querySelectorAll('video').forEach(function(v){v.pause()})", null)
        view.loadUrl("about:blank")
        loadedId = ""
        state = State()
        onChange(state)
    }

    fun togglePlay() {
        run("""var p = document.getElementById('movie_player'), v = document.querySelector('video');
            if (v) { if (v.paused || v.ended) { p && p.playVideo ? p.playVideo() : v.play(); }
                     else { p && p.pauseVideo ? p.pauseVideo() : v.pause(); } }""")
        main.postDelayed({ readPage() }, 150)
    }

    fun pause() = run("var v = document.querySelector('video'); if (v) v.pause();")

    fun seek(by: Double) {
        run("""var p = document.getElementById('movie_player'), v = document.querySelector('video');
            if (p && p.seekTo && p.getCurrentTime) { p.seekTo(Math.max(0, p.getCurrentTime() + ($by)), true); }
            else if (v) { v.currentTime = Math.max(0, v.currentTime + ($by)); }""")
        state = state.copy(elapsed = maxOf(0.0, state.elapsed + by))
        onChange(state)
    }

    fun skipAd() = run("""var b = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button');
        if (b) b.click();""")

    private fun run(body: String) = view.evaluateJavascript("(function(){$body})();", null)

    /** Host mode with the sound on the iPhone: this one plays the picture only. */
    var muted = false
        set(value) { if (value != field) { field = value; applyMuted() } }

    private fun applyMuted() = run("document.querySelectorAll('video').forEach(function(v){v.muted=$muted})")

    private fun poll() {
        if (!polling) return
        // A new video starts with its own sound: kept as it should be.
        if (muted) applyMuted()
        readPage()
        main.postDelayed(::poll, 1000)
    }

    private fun readPage() {
        // While a new page loads, the old one would still answer with the old video.
        if (loadedId.isEmpty() || loading) return
        view.evaluateJavascript(READING) { raw ->
            val json = runCatching { JSONTokener(raw).nextValue() as? String }.getOrNull() ?: return@evaluateJavascript
            val d = runCatching { JSONObject(json) }.getOrNull() ?: return@evaluateJavascript
            var next = state.copy(hasVideo = true, isPlaying = d.optBoolean("playing"), ended = d.optBoolean("ended"),
                isAd = d.optBoolean("ad"))
            next = next.copy(canSkipAd = next.isAd && d.optBoolean("skip"))
            if (!next.isAd) next = next.copy(elapsed = d.optDouble("t", 0.0), duration = d.optDouble("d", 0.0))
            // YouTube moved on by itself (its own autoplay): follow.
            val id = d.optString("id")
            if (id.isNotEmpty() && id != next.videoId) { next = next.copy(videoId = id, title = "", channel = ""); loadedId = id }
            d.optString("title").takeIf { it.isNotEmpty() && !next.isAd }?.let { next = next.copy(title = it) }
            d.optString("channel").takeIf { it.isNotEmpty() }?.let { next = next.copy(channel = it) }
            next = next.copy(notice = notice(d, (System.currentTimeMillis() - loadedAt) / 1000.0))
            if (next != state) { state = next; onChange(next) }
        }
    }

    private fun notice(d: JSONObject, seconds: Double): String {
        d.optString("error").takeIf { it.isNotEmpty() }?.let { return it }
        if (!d.optBoolean("video")) return if (seconds > 10) "YouTube showed no player" else ""
        if (d.optDouble("w", 0.0) == 0.0 && d.optDouble("t", 0.0) > 2) return "Playing without a picture"
        return ""
    }

    companion object {
        // Sizes in %, never vw/vh: a web view first laid out at no height keeps 100vh at 0 pixels.
        private val PLAYER_ONLY = """
(function () {
  var css =
    'html, body, ytd-app { background: #000 !important; overflow: hidden !important; }' +
    '#masthead-container, ytd-masthead, tp-yt-app-drawer, #guide, #secondary, #below, #chat,' +
    'ytd-miniplayer, ytd-popup-container, tp-yt-iron-overlay-backdrop, #related, #comments,' +
    '.ytp-chrome-top, .ytp-chrome-bottom, .ytp-gradient-top, .ytp-gradient-bottom,' +
    '.ytp-pause-overlay, .ytp-ce-element, .ytp-endscreen-content, .ytp-paid-content-overlay,' +
    '.iv-branding, .ytp-watermark, .ytp-cards-teaser, .ytp-spinner, .ytp-contextmenu,' +
    '.ytp-large-play-button, .ytp-bezel, .ytp-tooltip { display: none !important; }' +
    '#movie_player, #movie_player.html5-video-player { position: fixed !important; left: 0 !important;' +
    ' top: 0 !important; width: 100% !important; height: 100% !important; z-index: 2147483646 !important;' +
    ' background: #000 !important; }' +
    '#movie_player .html5-video-container { position: absolute !important; left: 0 !important;' +
    ' top: 0 !important; width: 100% !important; height: 100% !important; }' +
    '#movie_player video, #movie_player video.html5-main-video { position: absolute !important;' +
    ' left: 0 !important; top: 0 !important; width: 100% !important; height: 100% !important;' +
    ' object-fit: contain !important; visibility: visible !important; opacity: 1 !important; }';
  function add() {
    if (document.getElementById('__hud_player_only')) return;
    var s = document.createElement('style');
    s.id = '__hud_player_only';
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }
  add();
  document.addEventListener('DOMContentLoaded', add);
  var n = 0, t = setInterval(function () {
    add();
    window.dispatchEvent(new Event('resize'));
    if (++n > 10) clearInterval(t);
  }, 700);
})();
""".trimIndent()

        private val READING = """
(function () {
  var p = document.getElementById('movie_player');
  var v = (p && p.querySelector('video')) || document.querySelector('video');
  var skip = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button');
  var ch = document.querySelector('ytd-watch-metadata ytd-channel-name a, #owner #channel-name a, ytd-video-owner-renderer #channel-name a');
  var id = '';
  try { id = new URL(location.href).searchParams.get('v') || ''; } catch (e) {}
  var d = v && isFinite(v.duration) ? v.duration : 0;
  var err = document.querySelector('.ytp-error-content-wrap-reason, .ytp-error .ytp-error-content, yt-playability-error-supported-renderers #reason, ytd-enforcement-message-view-model');
  var errText = err && err.textContent ? err.textContent.trim().replace(/\s+/g, ' ').slice(0, 120) : '';
  return JSON.stringify({
    video: !!v, w: v ? v.videoWidth : 0, error: errText,
    playing: !!v && !v.paused && !v.ended, ended: !!v && v.ended,
    t: v ? v.currentTime : 0, d: d,
    ad: !!(p && (p.classList.contains('ad-showing') || p.classList.contains('ad-interrupting'))),
    skip: !!(skip && skip.offsetParent !== null),
    id: id,
    title: (document.title || '').replace(/^\(\d+\)\s*/, '').replace(/ - YouTube$/, ''),
    channel: ch ? ch.textContent.trim() : ''
  });
})();
""".trimIndent()
    }
}
