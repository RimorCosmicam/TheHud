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
    }

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
        // The panel is 1300 points wide: that is a desktop, not a phone. Phone layouts stretched
        // that wide are mostly whitespace.
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        let home = HomeSchemeHandler()
        configuration.setURLSchemeHandler(home, forURLScheme: "thehud")
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.darkFallback, injectionTime: .atDocumentEnd,
                         forMainFrameOnly: false))

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

        // The page starts below the glass bar and scrolls up underneath it.
        let top = BrowserMetrics.contentTopInset
        let scrollView = webView.scrollView
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        Self.setObscuredInsets(UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0), on: webView)

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
            state = next
        }
    }

    // ------------------------------------------------------------------ navigation

    public func load(_ url: URL) { webView.load(URLRequest(url: url)) }
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

    /// `target="_blank"` and `window.open`: one tab, so they open here.
    public func webView(_ webView: WKWebView,
                        createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction,
                        windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            webView.load(navigationAction.request)
        }
        return nil
    }

    /// Tells WebKit the top of the view is covered, the way Safari does for its own bar, so fixed
    /// headers sit below the glass instead of behind it. Private, so only if it is there.
    private static func setObscuredInsets(_ insets: UIEdgeInsets, on webView: WKWebView) {
        let selector = NSSelectorFromString("_setObscuredInsets:")
        guard webView.responds(to: selector),
              let method = class_getInstanceMethod(type(of: webView), selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UIEdgeInsets) -> Void
        let set = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        set(webView, selector, insets)
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

/// Puts the browser's one web view on the canvas.
public struct WebBrowserView: UIViewRepresentable {
    public let browser: WebBrowser

    public init(_ browser: WebBrowser) { self.browser = browser }

    public func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .black
        host.isUserInteractionEnabled = false
        return host
    }

    // The web view is re-parented rather than recreated, so unplugging the glasses and plugging
    // them back in finds the page where it was left.
    public func updateUIView(_ host: UIView, context: Context) {
        let webView = browser.webView
        if webView.superview !== host {
            webView.removeFromSuperview()
            webView.frame = host.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(webView)
        }
    }
}
#endif
