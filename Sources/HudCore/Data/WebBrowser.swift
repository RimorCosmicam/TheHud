#if os(iOS)
import SwiftUI
import WebKit

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
public final class WebBrowser: NSObject, WKNavigationDelegate {
    public struct State: Equatable {
        public var title = ""
        public var url = ""
        public var canGoBack = false
        public var canGoForward = false
        public var loading: Double?
    }

    public let webView: WKWebView
    public private(set) var state = State() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((State) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    public override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.darkFallback, injectionTime: .atDocumentEnd,
                         forMainFrameOnly: false))

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1352, height: 821),
                            configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.indicatorStyle = .white
        webView.overrideUserInterfaceStyle = .dark
        // The glasses take no touches; the phone's cursor is the only way in.
        webView.isUserInteractionEnabled = false

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
                next.url = (url.host ?? url.absoluteString) + (url.path == "/" ? "" : url.path)
            }
            next.canGoBack = webView.canGoBack
            next.canGoForward = webView.canGoForward
            next.loading = webView.isLoading ? webView.estimatedProgress : nil
            state = next
        }
    }

    // ------------------------------------------------------------------ navigation

    public func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    public func back() { webView.goBack() }
    public func forward() { webView.goForward() }
    public func reload() { webView.isLoading ? webView.stopLoading() : webView.reload() }

    // ------------------------------------------------------------------ pointer

    /// A left click at a point in the page's own coordinates. Reports whether it landed on
    /// something that takes text, so the phone knows to raise the keyboard.
    public func click(at point: CGPoint) async -> Bool {
        let script = """
        (function (x, y) {
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
        })(\(Double(point.x)), \(Double(point.y)));
        """
        return (try? await webView.evaluateJavaScript(script) as? Bool) ?? false
    }

    /// Scroll the nearest scrollable thing under the point. Positive ticks move content up.
    public func scroll(ticks: Int, at point: CGPoint) {
        let pixels = Double(ticks) * 48
        let script = """
        (function (x, y, dy) {
          var el = document.elementFromPoint(x, y);
          while (el && el !== document.body && el !== document.documentElement) {
            var s = getComputedStyle(el);
            if (/(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight) {
              el.scrollBy({top: dy}); return;
            }
            el = el.parentElement;
          }
          window.scrollBy({top: dy});
        })(\(Double(point.x)), \(Double(point.y)), \(pixels));
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
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
