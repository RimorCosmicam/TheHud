package com.thehud.web

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.ui.geometry.Offset
import androidx.webkit.UserAgentMetadata
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import org.json.JSONArray

/**
 * One browser tab: a WebView kept outside Compose, so the page survives the glasses coming and
 * going, and so the phone has a handle on it.
 *
 * Unlike the iPhone, Android lets an app hand a view real mouse events. A click is a mouse
 * press and release, hovering is a hover, the wheel is a wheel: pages see a mouse, with the
 * trust that brings (videos start, menus open on hover) and none of the iPhone's JavaScript
 * stand-ins.
 */
@SuppressLint("SetJavaScriptEnabled")
class WebTab(context: Context, private val onChange: (WebTab) -> Unit) {
    data class State(
        val title: String = "",
        val url: String = "",
        val canGoBack: Boolean = false,
        val canGoForward: Boolean = false,
        val loading: Float? = null,
        val isHome: Boolean = true,
        /** The whole address, for favourites. */
        val address: String = "",
    )

    var state = State()
        private set

    val view: WebView = WebView(context).apply {
        setBackgroundColor(Color.BLACK)
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.mediaPlaybackRequiresUserGesture = false
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = true
        settings.setSupportZoom(false)
        // The panel is a desktop's width; phone layouts stretched across it are mostly air.
        desktop(settings)
        // A white page is the brightest thing the glasses can show, and it blinds.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
            WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, true)
        }
        isFocusable = true
        isFocusableInTouchMode = true
        webViewClient = object : WebViewClient() {
            // Every link stays here: nothing hands the wearer off to another app.
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val scheme = request.url.scheme ?: return true
                return scheme != "http" && scheme != "https" && scheme != "about" && scheme != "data"
            }
            override fun onPageFinished(view: WebView, url: String?) = refresh()
            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) = refresh()
        }
        webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) = refresh()
            override fun onReceivedTitle(view: WebView, title: String?) = refresh()
        }
    }

    private fun refresh() {
        val url = view.url.orEmpty()
        val home = url.isEmpty() || url.startsWith("data:") || url == "about:blank"
        val host = runCatching { android.net.Uri.parse(url) }.getOrNull()
        val short = if (home) "" else (host?.host ?: url) + (host?.path?.takeIf { it != "/" } ?: "")
        state = State(
            title = view.title.orEmpty().takeIf { !home } ?: "",
            url = short,
            canGoBack = view.canGoBack(),
            canGoForward = view.canGoForward(),
            loading = if (view.progress in 1..99) view.progress / 100f else null,
            isHome = home,
            address = if (home) "" else url,
        )
        onChange(this)
    }

    fun load(url: String) = view.loadUrl(url)
    fun goHome(html: String) {
        view.loadDataWithBaseURL("https://thehud.local/", html, "text/html", "utf-8", null)
    }
    fun back() { if (view.canGoBack()) view.goBack() }
    fun forward() { if (view.canGoForward()) view.goForward() }
    fun reload() { if (view.progress < 100) view.stopLoading() else view.reload() }

    /** Takes the view out of whatever held it, to be put somewhere else. */
    fun detach() { (view.parent as? ViewGroup)?.removeView(view) }

    // ------------------------------------------------------------------ the mouse

    /** Canvas points inside the panel to the view's own pixels. */
    private fun pixels(p: Offset, panelWidth: Float): Offset {
        val scale = if (panelWidth > 0 && view.width > 0) view.width / panelWidth else 1f
        return Offset(p.x * scale, p.y * scale)
    }

    private fun mouse(action: Int, at: Offset, buttons: Int, down: Long, scroll: Float = 0f): MotionEvent {
        val props = MotionEvent.PointerProperties().apply { id = 0; toolType = MotionEvent.TOOL_TYPE_MOUSE }
        val coords = MotionEvent.PointerCoords().apply {
            x = at.x; y = at.y; pressure = 1f; size = 1f
            if (scroll != 0f) setAxisValue(MotionEvent.AXIS_VSCROLL, scroll)
        }
        return MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, 1, arrayOf(props), arrayOf(coords),
            0, buttons, 1f, 1f, 0, 0, InputDevice.SOURCE_MOUSE, 0)
    }

    /**
     * A real mouse click: down, button press, button release, up. Chromium reads the button from
     * the press and release, and ignores a bare down and up from a mouse.
     */
    fun click(p: Offset, panelWidth: Float, right: Boolean = false) {
        val at = pixels(p, panelWidth)
        val button = if (right) MotionEvent.BUTTON_SECONDARY else MotionEvent.BUTTON_PRIMARY
        val down = SystemClock.uptimeMillis()
        view.requestFocus()
        fun send(action: Int, buttons: Int, generic: Boolean) {
            val e = mouse(action, at, buttons, down)
            if (generic) setActionButton(e, button)
            if (generic) view.dispatchGenericMotionEvent(e) else view.dispatchTouchEvent(e)
            e.recycle()
        }
        send(MotionEvent.ACTION_DOWN, button, generic = false)
        send(MotionEvent.ACTION_BUTTON_PRESS, button, generic = true)
        send(MotionEvent.ACTION_BUTTON_RELEASE, 0, generic = true)
        send(MotionEvent.ACTION_UP, 0, generic = false)
    }

    fun hover(p: Offset, panelWidth: Float) {
        val e = mouse(MotionEvent.ACTION_HOVER_MOVE, pixels(p, panelWidth), 0, SystemClock.uptimeMillis())
        view.dispatchGenericMotionEvent(e)
        e.recycle()
    }

    /** Positive ticks move the page's content up, as a trackpad scroll down does. */
    fun scroll(ticks: Int, p: Offset, panelWidth: Float) {
        val e = mouse(MotionEvent.ACTION_SCROLL, pixels(p, panelWidth), 0, SystemClock.uptimeMillis(), -ticks.toFloat())
        view.dispatchGenericMotionEvent(e)
        e.recycle()
    }

    // ------------------------------------------------------------------ typing

    fun insert(text: String) {
        view.evaluateJavascript("document.execCommand('insertText', false, ${JSONArray(listOf(text)).toString().drop(1).dropLast(1)});", null)
    }

    fun deleteBackward(count: Int) {
        if (count > 0) view.evaluateJavascript("for (var i = 0; i < $count; i++) document.execCommand('delete');", null)
    }

    fun submit() {
        view.evaluateJavascript("""
            (function () {
              var el = document.activeElement; if (!el) return;
              var o = {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true};
              var go = el.dispatchEvent(new KeyboardEvent('keydown', o));
              el.dispatchEvent(new KeyboardEvent('keypress', o));
              el.dispatchEvent(new KeyboardEvent('keyup', o));
              if (go && el.form && el.tagName !== 'TEXTAREA') { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }
            })();
        """.trimIndent(), null)
    }

    /** Whether what was clicked takes text, so the phone knows to raise the keyboard. */
    fun focusTakesText(answer: (Boolean) -> Unit) {
        view.evaluateJavascript("""
            (function () { var el = document.activeElement; if (!el) return false;
              return el.isContentEditable || el.tagName === 'TEXTAREA' ||
                (el.tagName === 'INPUT' && !/^(button|submit|checkbox|radio|reset|file|image|range|color)$/i.test(el.type)); })();
        """.trimIndent()) { answer(it == "true") }
    }

    companion object {
        /** The button a press or release is about; settable only by reflection. */
        private val actionButton = runCatching {
            MotionEvent::class.java.getMethod("setActionButton", Int::class.javaPrimitiveType)
        }.getOrNull()

        private fun setActionButton(e: MotionEvent, button: Int) { runCatching { actionButton?.invoke(e, button) } }

        /** The engine's real version: sites (Google's sign-in first) refuse a browser that claims an old one. */
        private val engine: String = runCatching { WebView.getCurrentWebViewPackage()?.versionName }.getOrNull()
            ?.takeIf { it.isNotBlank() } ?: "156.0.0.0"
        private val major = engine.substringBefore('.')

        val DESKTOP_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$major.0.0.0 Safari/537.36"

        /**
         * Desktop Chrome, said the same way everywhere: the user agent, the client hints (which
         * otherwise still say "Android WebView" on a phone) and no X-Requested-With naming this
         * app. Google signs a browser in only when all of it agrees.
         */
        fun desktop(settings: WebSettings) {
            desktop(settings)
            if (WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA)) runCatching {
                fun brand(name: String, version: String) =
                    UserAgentMetadata.BrandVersion.Builder().setBrand(name).setMajorVersion(version.substringBefore('.'))
                        .setFullVersion(version).build()
                WebSettingsCompat.setUserAgentMetadata(settings, UserAgentMetadata.Builder()
                    .setBrandVersionList(listOf(brand("Google Chrome", engine), brand("Chromium", engine), brand("Not_A Brand", "24.0.0.0")))
                    .setFullVersion(engine).setPlatform("Linux").setPlatformVersion("").setArchitecture("x86")
                    .setModel("").setMobile(false).setBitness(64).setWow64(false).build())
            }
            if (WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) runCatching {
                WebSettingsCompat.setRequestedWithHeaderOriginAllowList(settings, emptySet())
            }
        }
    }
}

/** The start page: favourites as tiles, in the HUD's own look. */
object HomePage {
    @kotlinx.serialization.Serializable
    data class Favorite(val title: String, val url: String)

    val defaults = listOf(
        Favorite("YouTube", "https://www.youtube.com"),
        Favorite("Google", "https://www.google.com"),
        Favorite("Wikipedia", "https://www.wikipedia.org"),
        Favorite("Maps", "https://www.openstreetmap.org"),
    )

    fun html(favorites: List<Favorite>) = buildString {
        append("""<!doctype html><html><head><meta name="viewport" content="width=device-width"><meta name="color-scheme" content="dark">
<style>html,body{background:#000;color:#fff;margin:0;font-family:sans-serif}
.grid{display:flex;flex-wrap:wrap;gap:24px;padding:140px 72px}
a{display:flex;flex-direction:column;justify-content:flex-end;width:220px;height:150px;padding:22px;box-sizing:border-box;
border-radius:22px;background:rgba(255,255,255,.08);color:#fff;text-decoration:none;font-weight:900;font-size:22px}
a span{color:rgba(255,255,255,.5);font-size:15px;font-weight:600;margin-top:6px}
a:hover{background:rgba(255,255,255,.18)}</style></head><body><div class="grid">""")
        for (f in favorites) {
            val host = android.net.Uri.parse(f.url).host.orEmpty().removePrefix("www.")
            append("<a href=\"${f.url}\">${f.title}<span>$host</span></a>")
        }
        append("</div></body></html>")
    }
}

/** Typed into the address bar: an address, or something to search for. */
object AddressInput {
    fun url(input: String): String? {
        val text = input.trim()
        if (text.isEmpty()) return null
        if (text.startsWith("http://") || text.startsWith("https://")) return text
        if (!text.contains(' ') && text.contains('.') && !text.endsWith('.')) return "https://$text"
        return "https://www.google.com/search?q=" + java.net.URLEncoder.encode(text, "UTF-8")
    }
}
