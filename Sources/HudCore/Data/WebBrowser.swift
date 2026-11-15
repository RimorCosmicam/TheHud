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
        // WebKit's own element fullscreen, the one Safari uses: YouTube and every other player
        // get the real Fullscreen API, `:fullscreen` styles and all. WebKit lifts the web view
        // into a fullscreen window on the scene it is in, which is the glasses.
        configuration.preferences.isElementFullscreenEnabled = true
        if #unavailable(iOS 26.0) {
            // Before `obscuredContentInsets`, the page's fixed bars have to be moved by hand.
            configuration.userContentController.addUserScript(
                WKUserScript(source: PageScripts.bridge(inset: BrowserMetrics.contentTopInset),
                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1352, height: 821),
                            configuration: configuration)
        super.init()
        home.browser = self

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.indicatorStyle = .white
        webView.overrideUserInterfaceStyle = .dark
        // The glasses take no touches; the phone's cursor is the only way in.
        webView.isUserInteractionEnabled = false

        // The glass bar covers the top of the page. Telling WebKit so is what Safari does: the
        // page starts below the bar, scrolls up under it, and the page's own fixed headers sit
        // below it with the content running under them.
        // Safari sets both: a fixed content inset for where the page starts, and the obscured
        // inset for where WebKit lays out the page's fixed elements.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        applyChromeInset(BrowserMetrics.contentTopInset)
        if #available(iOS 26.0, *) {
            webView.obscuredContentInsets = UIEdgeInsets(top: BrowserMetrics.contentTopInset,
                                                         left: 0, bottom: 0, right: 0)
        }

        observations = [
            webView.observe(\.title) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.url) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.refresh() },
            webView.observe(\.fullscreenState) { [weak self] _, _ in self?.fullscreenStateChanged() },
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

    /// The host the web view lives in when it is not fullscreen. WebKit takes the view out
    /// for fullscreen and puts it back where it found it, which may be a host SwiftUI has since
    /// thrown away; this is where it really belongs.
    weak var host: WebHostController?

    nonisolated private func fullscreenStateChanged() {
        MainActor.assumeIsolated {
            let on = webView.fullscreenState != .notInFullscreen
            if !on, webView.fullscreenState == .notInFullscreen {
                // Once WebKit has finished putting it back.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.host?.show(self.webView, force: true)
                }
            }
            guard on != state.isFullscreen else { return }
            state.isFullscreen = on
        }
    }

    /// Where the page starts: below the bar, scrolling up under it.
    private func applyChromeInset(_ top: CGFloat) {
        let scrollView = webView.scrollView
        let insets = UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        scrollView.contentInset = insets
        scrollView.verticalScrollIndicatorInsets = insets
        scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: -top)
    }

    /// From the phone: leave fullscreen, or put the page's video player into it.
    public func toggleFullscreen() {
        if state.isFullscreen {
            webView.evaluateJavaScript("document.exitFullscreen && document.exitFullscreen();",
                                       completionHandler: nil)
            webView.closeAllMediaPresentations {}
        } else {
            webView.evaluateJavaScript("""
            (function () {
              var v = document.querySelector('video');
              var el = v ? (v.closest('#movie_player, .html5-video-player, [data-player]') || v)
                         : document.documentElement;
              (el.requestFullscreen || el.webkitRequestFullscreen).call(el);
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
public struct WebBrowserView: UIViewControllerRepresentable {
    public let browser: WebBrowser

    public init(_ browser: WebBrowser) {
        self.browser = browser
    }

    public func makeUIViewController(context: Context) -> WebHostController {
        WebHostController()
    }

    public func updateUIViewController(_ host: WebHostController, context: Context) {
        browser.host = host
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
    func show(_ webView: WKWebView, force: Bool = false) {
        guard webView.superview !== view else { return }
        // While WebKit has it in its fullscreen window, taking it back would tear the video
        // out of fullscreen and leave that window black.
        guard force || webView.fullscreenState == .notInFullscreen else { return }
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
