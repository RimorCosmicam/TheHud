#if os(iOS)
import SwiftUI
import WebKit
import ObjectiveC

/// The browser: one `WKWebView`, owned here rather than by a view.
///
/// A `WKWebView` is the only way anything that is not ours can appear on the canvas: iOS has no
/// way to host another app inside this one, so a web view is the whole of the answer to "run
/// other apps".
///
/// It lives outside SwiftUI because the glasses scene comes and goes with the cable while the
/// page should not, and because the phone has to drive it — back, reload, a click at a point,
/// keystrokes — which needs a handle, not a view description.
///
/// It is forced dark. A white page is the brightest thing a birdbath display can produce, and on
/// the Air that both blinds and destroys the transparency the HUD depends on. Pages that honour
/// `prefers-color-scheme` follow; the rest get the injected fallback below, which is deliberately
/// crude — it is a brightness cap, not a reader mode.
@MainActor
public final class WebBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    public struct State: Equatable {
        public var title = ""
        public var url = ""
        /// The full address, for favourites.
        public var absoluteURL = ""
        public var canGoBack = false
        public var canGoForward = false
        public var loading: Double?
        public var isHome = true
        /// The page has an element in (our) fullscreen.
        public var isFullscreen = false
    }

    /// Links that ask for a new window. One tab would open them in place; the controller opens
    /// a tab.
    public var onOpenInNewTab: ((URLRequest) -> Void)?

    /// The start page lives at a scheme of our own, so it is a real history entry: back from a
    /// site lands on it, and reload redraws it with the current favourites.
    public static let homeURL = URL(string: "thehud://home")!

    /// Supplies the start page's HTML each time it loads.
    public var homeHTML: () -> String = { HomePage.html(Favorite.defaults) }

    public let webView: WKWebView
    public private(set) var state = State() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((State) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    public override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // Every click is synthetic — the glasses take no touches — so WebKit never sees a "user
        // gesture" and would refuse to start any video with sound. The cursor is the user.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        // The panel is 1300 points wide: that is a desktop, not a phone. Phone layouts stretched
        // that wide are mostly whitespace.
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        let home = HomeSchemeHandler()
        configuration.setURLSchemeHandler(home, forURLScheme: "thehud")
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.darkFallback, injectionTime: .atDocumentEnd,
                         forMainFrameOnly: false))
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.fullscreenShim, injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))
        let relay = MessageRelay()
        configuration.userContentController.add(relay, name: "hudFullscreen")

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1352, height: 821),
                            configuration: configuration)
        super.init()
        home.browser = self
        relay.browser = self

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.indicatorStyle = .white
        webView.overrideUserInterfaceStyle = .dark
        // The glasses take no touches; the phone's cursor is the only way in.
        webView.isUserInteractionEnabled = false

        // The page starts below the glass bar and scrolls up underneath it. That is done with
        // the safe area, not by hand: `WebBrowserView` gives the web view a top safe-area inset
        // the height of the bar, and WebKit treats a safe area as covered — the content starts
        // below it, scrolls up beneath it, and fixed headers (YouTube's search bar) stay below
        // it rather than hiding behind the glass. It is the mechanism that keeps pages clear of
        // the notch, which is exactly this problem.
        webView.scrollView.contentInsetAdjustmentBehavior = .always

        observations = [
            webView.observe(\.title) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.url) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.refresh() },
        ]
    }

    // KVO fires on the main thread for a WKWebView, which is the only thread it may be used on.
    nonisolated private func refresh() {
        MainActor.assumeIsolated {
            var next = State()
            next.title = webView.title ?? ""
            if let url = webView.url {
                next.isHome = url.scheme == "thehud"
                if !next.isHome {
                    next.url = (url.host ?? url.absoluteString) + (url.path == "/" ? "" : url.path)
                    next.absoluteURL = url.absoluteString
                }
            }
            next.canGoBack = webView.canGoBack
            next.canGoForward = webView.canGoForward
            next.loading = webView.isLoading ? webView.estimatedProgress : nil
            next.isFullscreen = state.isFullscreen
            state = next
        }
    }

    // ------------------------------------------------------------------ navigation

    public func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    // ------------------------------------------------------------------ fullscreen

    /// No bar over a fullscreen video, so `WebBrowserView` drops the safe area with it.
    fileprivate func fullscreenChanged(_ on: Bool) {
        guard on != state.isFullscreen else { return }
        state.isFullscreen = on
    }

    /// From the phone: leave fullscreen, or put the page's video (the player around it, where
    /// there is one, so its own controls come too) into fullscreen.
    public func toggleFullscreen() {
        if state.isFullscreen {
            webView.evaluateJavaScript("window.__hudExitFullscreen && window.__hudExitFullscreen();",
                                       completionHandler: nil)
        } else {
            webView.evaluateJavaScript("""
            (function () {
              var v = document.querySelector('video');
              var el = v ? (v.closest('#movie_player, .html5-video-player, [data-player]') || v)
                         : document.documentElement;
              el.requestFullscreen();
            })();
            """, completionHandler: nil)
        }
    }
    public func goHome() { load(Self.homeURL) }

    /// Redraw the start page if it is showing, after the favourites change.
    public func refreshHomeIfShowing() {
        if state.isHome { webView.reload() }
    }
    public func back() { webView.goBack() }
    public func forward() { webView.goForward() }

    public func reload() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    // ------------------------------------------------------------------ pointer

    /// A left click at a point in the page's own coordinates. Reports whether it landed on
    /// something that takes text, so the phone knows to raise the keyboard.
    public func click(at point: CGPoint) async -> Bool {
        let page = documentPoint(point)
        let script = """
        (function (dx, dy) {
          var x = dx - window.scrollX, y = dy - window.scrollY;
          var el = document.elementFromPoint(x, y);
          if (!el) return false;
          var o = {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y,
                   button: 0, buttons: 1};
          try { el.dispatchEvent(new PointerEvent('pointerdown', o)); } catch (e) {}
          el.dispatchEvent(new MouseEvent('mousedown', o));
          var editable = el.isContentEditable
            || (el.tagName === 'INPUT' && !/^(button|submit|checkbox|radio|reset|file|image|range|color)$/i.test(el.type))
            || el.tagName === 'TEXTAREA';
          if (editable || el.tabIndex >= 0) { el.focus(); }
          o.buttons = 0;
          try { el.dispatchEvent(new PointerEvent('pointerup', o)); } catch (e) {}
          el.dispatchEvent(new MouseEvent('mouseup', o));
          el.click();
          return !!editable;
        })(\(Double(page.x)), \(Double(page.y)));
        """
        return (try? await webView.evaluateJavaScript(script) as? Bool) ?? false
    }

    /// The cursor moved: hover menus open, video controls wake up. Sent as the mouse events a
    /// desktop browser would send, to whatever is under the point.
    public func hover(at point: CGPoint) {
        let page = documentPoint(point)
        let script = """
        (function (dx, dy) {
          var x = dx - window.scrollX, y = dy - window.scrollY;
          var el = document.elementFromPoint(x, y);
          if (!el) return;
          var o = {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y};
          var last = window.__hudHover;
          if (last !== el) {
            if (last) {
              last.dispatchEvent(new MouseEvent('mouseout', o));
              try { last.dispatchEvent(new PointerEvent('pointerout', o)); } catch (e) {}
              last.dispatchEvent(new MouseEvent('mouseleave', {bubbles: false, clientX: x, clientY: y}));
            }
            el.dispatchEvent(new MouseEvent('mouseover', o));
            try { el.dispatchEvent(new PointerEvent('pointerover', o)); } catch (e) {}
            el.dispatchEvent(new MouseEvent('mouseenter', {bubbles: false, clientX: x, clientY: y}));
            window.__hudHover = el;
          }
          try { el.dispatchEvent(new PointerEvent('pointermove', o)); } catch (e) {}
          el.dispatchEvent(new MouseEvent('mousemove', o));
        })(\(Double(page.x)), \(Double(page.y)));
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Scroll the nearest scrollable thing under the point. Positive ticks move content up.
    public func scroll(ticks: Int, at point: CGPoint) {
        let pixels = Double(ticks) * 48
        let page = documentPoint(point)
        let script = """
        (function (dx, dy0, dy) {
          var x = dx - window.scrollX, y = dy0 - window.scrollY;
          var el = document.elementFromPoint(x, y);
          while (el && el !== document.body && el !== document.documentElement) {
            var s = getComputedStyle(el);
            if (/(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight) {
              el.scrollBy({top: dy}); return;
            }
            el = el.parentElement;
          }
          window.scrollBy({top: dy});
        })(\(Double(page.x)), \(Double(page.y)), \(pixels));
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// A point on the web view to a point in the document. Going through the scroll view rather
    /// than trusting the page's own client coordinates keeps this right whatever the glass bar's
    /// inset does to the viewport, and at any zoom.
    private func documentPoint(_ point: CGPoint) -> CGPoint {
        let scrollView = webView.scrollView
        let zoom = max(scrollView.zoomScale, 0.01)
        return CGPoint(x: (point.x + scrollView.contentOffset.x) / zoom,
                       y: (point.y + scrollView.contentOffset.y) / zoom)
    }

    // ------------------------------------------------------------------ policy

    /// Every link stays in here. A plain `.allow` lets iOS hand universal links — youtube.com,
    /// maps, most big sites — to their app, which takes the wearer out of the HUD entirely. The
    /// value two past `.allow` is WebKit's "allow without trying an app link", the one Safari
    /// itself uses. Anything that is not web at all (a `youtube://`, an `intent://`) is dropped.
    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "data", "blob", "thehud"].contains(scheme) else {
            decisionHandler(.cancel)
            return
        }
        let noAppLink = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2)
        decisionHandler(noAppLink ?? .allow)
    }

    /// `target="_blank"` and `window.open`: a new tab, as a desktop browser would.
    public func webView(_ webView: WKWebView,
                        createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction,
                        windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let open = onOpenInNewTab {
            open(navigationAction.request)
        } else {
            webView.load(navigationAction.request)
        }
        return nil
    }

    /// Element fullscreen for an iPhone web view that has none of its own.
    ///
    /// iOS would either refuse (`requestFullscreen` does not exist on iPhone) or hand a video to
    /// the system player — on the phone's screen, not the glasses. So the page gets a stand-in:
    /// the element is pinned over the whole viewport, the document reports it as the fullscreen
    /// element and fires the usual events, so players such as YouTube's switch to their own
    /// fullscreen layout, and the app is told so it can give the browser the whole canvas.
    private static let fullscreenShim = """
    (function () {
      if (window.__hudFullscreen) return;
      window.__hudFullscreen = true;
      var current = null, saved = null, savedRoot = '';
      function post(on) {
        try { window.webkit.messageHandlers.hudFullscreen.postMessage(on); } catch (e) {}
      }
      function fire(el) {
        ['fullscreenchange', 'webkitfullscreenchange'].forEach(function (t) {
          var target = (el && el.isConnected) ? el : document;
          target.dispatchEvent(new Event(t, {bubbles: true}));
        });
      }
      function enter(el) {
        if (current === el) return Promise.resolve();
        if (current) exit();
        current = el;
        saved = el.getAttribute('style');
        el.style.cssText += ';position:fixed!important;left:0!important;top:0!important;' +
          'width:100vw!important;height:100vh!important;max-width:none!important;' +
          'max-height:none!important;margin:0!important;transform:none!important;' +
          'z-index:2147483647!important;background:#000!important';
        savedRoot = document.documentElement.style.overflow;
        document.documentElement.style.overflow = 'hidden';
        post(true);
        fire(el);
        setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 60);
        return Promise.resolve();
      }
      function exit() {
        if (!current) return Promise.resolve();
        var el = current;
        current = null;
        if (saved === null) el.removeAttribute('style'); else el.setAttribute('style', saved);
        document.documentElement.style.overflow = savedRoot;
        post(false);
        fire(el);
        setTimeout(function () { window.dispatchEvent(new Event('resize')); }, 60);
        return Promise.resolve();
      }
      function getter(name, fn) {
        try { Object.defineProperty(document, name, {get: fn, configurable: true}); } catch (e) {}
      }
      getter('fullscreenElement', function () { return current; });
      getter('webkitFullscreenElement', function () { return current; });
      getter('webkitCurrentFullScreenElement', function () { return current; });
      getter('fullscreenEnabled', function () { return true; });
      getter('webkitFullscreenEnabled', function () { return true; });
      getter('webkitFullScreenKeyboardInputAllowed', function () { return true; });
      getter('fullscreen', function () { return !!current; });
      getter('webkitIsFullScreen', function () { return !!current; });
      Element.prototype.requestFullscreen = function () { return enter(this); };
      Element.prototype.webkitRequestFullscreen = Element.prototype.requestFullscreen;
      Element.prototype.webkitRequestFullScreen = Element.prototype.requestFullscreen;
      if (window.HTMLVideoElement) {
        HTMLVideoElement.prototype.webkitEnterFullscreen = function () { enter(this); };
        HTMLVideoElement.prototype.webkitEnterFullScreen = HTMLVideoElement.prototype.webkitEnterFullscreen;
        HTMLVideoElement.prototype.webkitExitFullscreen = function () { exit(); };
        try {
          Object.defineProperty(HTMLVideoElement.prototype, 'webkitSupportsFullscreen',
                                {get: function () { return true; }, configurable: true});
        } catch (e) {}
      }
      document.exitFullscreen = exit;
      document.webkitExitFullscreen = exit;
      document.webkitCancelFullScreen = exit;
      window.__hudExitFullscreen = exit;
      document.addEventListener('keydown', function (e) { if (e.key === 'Escape') exit(); }, true);
      window.addEventListener('pagehide', function () { if (current) post(false); });
    })();
    """

    // ------------------------------------------------------------------ keyboard

    /// Text typed on the phone, into whatever the page has focused.
    public func insert(_ text: String) {
        guard let literal = Self.jsString(text) else { return }
        webView.evaluateJavaScript(
            "document.execCommand('insertText', false, \(literal));", completionHandler: nil)
    }

    public func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        webView.evaluateJavaScript(
            "for (var i = 0; i < \(count); i++) document.execCommand('delete');",
            completionHandler: nil)
    }

    /// Return: submit the focused field's form, or send Enter for pages that listen for it.
    public func submit() {
        let script = """
        (function () {
          var el = document.activeElement;
          if (!el) return;
          var o = {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true};
          var go = el.dispatchEvent(new KeyboardEvent('keydown', o));
          el.dispatchEvent(new KeyboardEvent('keypress', o));
          el.dispatchEvent(new KeyboardEvent('keyup', o));
          if (go && el.form && el.tagName !== 'TEXTAREA') {
            el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit();
          }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private static func jsString(_ text: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let array = String(data: data, encoding: .utf8) else { return nil }
        return String(array.dropFirst().dropLast())
    }

    /// Asks for dark first; only if the page has no dark styling of its own does it cap the
    /// brightness by inverting, and images are inverted back so photographs survive.
    private static let darkFallback = """
    (function () {
      var meta = document.createElement('meta');
      meta.name = 'color-scheme';
      meta.content = 'dark light';
      document.head && document.head.appendChild(meta);

      var declared = window.matchMedia
        && window.matchMedia('(prefers-color-scheme: dark)').matches;
      var body = document.body;
      if (!body) return;
      var background = getComputedStyle(body).backgroundColor;
      var isLight = /rgba?\\((2[0-4][0-9]|25[0-5]),\\s*(2[0-4][0-9]|25[0-5])/.test(background);
      if (declared && !isLight) return;
      if (!isLight) return;

      var style = document.createElement('style');
      style.textContent =
        'html{filter:invert(1) hue-rotate(180deg);background:#000!important}' +
        'img,video,canvas,svg,picture,iframe{filter:invert(1) hue-rotate(180deg)}';
      document.documentElement.appendChild(style);
    })();
    """
}

/// Relays the page's fullscreen messages without the content controller holding the browser.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var browser: WebBrowser?

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let on = (message.body as? Bool) ?? ((message.body as? NSNumber)?.boolValue ?? false)
        MainActor.assumeIsolated { browser?.fullscreenChanged(on) }
    }
}

/// Serves `thehud://home`.
private final class HomeSchemeHandler: NSObject, WKURLSchemeHandler {
    weak var browser: WebBrowser?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let html = MainActor.assumeIsolated { browser?.homeHTML() } ?? HomePage.html([])
        let data = Data(html.utf8)
        let response = URLResponse(url: task.request.url ?? WebBrowser.homeURL,
                                   mimeType: "text/html", expectedContentLength: data.count,
                                   textEncodingName: "utf-8")
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Puts the active tab's web view on the canvas.
///
/// A view controller rather than a plain view, because a view controller is what can add to the
/// safe area: `topInset` becomes the web view's top safe-area inset, which is how the page knows
/// the glass bar is there (see `WebBrowser`).
public struct WebBrowserView: UIViewControllerRepresentable {
    public let browser: WebBrowser
    public var topInset: CGFloat

    public init(_ browser: WebBrowser, topInset: CGFloat = BrowserMetrics.contentTopInset) {
        self.browser = browser
        self.topInset = topInset
    }

    public func makeUIViewController(context: Context) -> WebHostController {
        WebHostController()
    }

    public func updateUIViewController(_ host: WebHostController, context: Context) {
        let insets = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        if host.additionalSafeAreaInsets != insets { host.additionalSafeAreaInsets = insets }
        host.show(browser.webView)
    }
}

public final class WebHostController: UIViewController {
    public override func loadView() {
        let view = UIView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        self.view = view
    }

    /// The web view is re-parented rather than recreated, so switching tabs or unplugging the
    /// glasses finds each page where it was left.
    func show(_ webView: WKWebView) {
        guard webView.superview !== view else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)
    }
}

/// The glass under the browser's bar: UIKit's own blur, the same one Safari puts over its pages.
/// It samples the web view's layers directly, which a SwiftUI material over a hosted view does
/// not reliably do.
public struct GlassBackdrop: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        view.isUserInteractionEnabled = false
        return view
    }

    public func updateUIView(_ view: UIVisualEffectView, context: Context) {}
}
#endif
