#if os(iOS)
import SwiftUI
import WebKit

/// The browser's content area.
///
/// A `WKWebView` is the only way anything that is not ours can appear on the canvas: iOS has no
/// way to host another app inside this one, so a web view is the whole of the answer to "run
/// other apps".
///
/// It is forced dark. A white page is the brightest thing a birdbath display can produce, and on
/// the Air that both blinds and destroys the transparency the HUD depends on. Pages that honour
/// `prefers-color-scheme` follow; the rest get the injected fallback below, which is deliberately
/// crude — it is a brightness cap, not a reader mode.
public struct WebContentView: UIViewRepresentable {
    public var url: URL
    public var onTitleChange: ((String) -> Void)?
    public var onURLChange: ((String) -> Void)?

    public init(url: URL,
                onTitleChange: ((String) -> Void)? = nil,
                onURLChange: ((String) -> Void)? = nil) {
        self.url = url
        self.onTitleChange = onTitleChange
        self.onURLChange = onURLChange
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let darken = WKUserScript(source: Self.darkFallback,
                                  injectionTime: .atDocumentEnd,
                                  forMainFrameOnly: false)
        configuration.userContentController.addUserScript(darken)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.indicatorStyle = .white
        webView.overrideUserInterfaceStyle = .dark
        webView.load(URLRequest(url: url))
        context.coordinator.observe(webView)
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url && !webView.isLoading {
            webView.load(URLRequest(url: url))
        }
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

    public final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebContentView
        private var observations: [NSKeyValueObservation] = []

        init(_ parent: WebContentView) {
            self.parent = parent
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.title, options: [.new]) { [weak self] _, change in
                    if let title = change.newValue ?? nil, !title.isEmpty {
                        self?.parent.onTitleChange?(title)
                    }
                },
                webView.observe(\.url, options: [.new]) { [weak self] _, change in
                    if let url = change.newValue ?? nil {
                        let shown = (url.host ?? "") + url.path
                        self?.parent.onURLChange?(shown)
                    }
                },
            ]
        }
    }
}
#endif
