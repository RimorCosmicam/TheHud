import Foundation
import WebKit
#if os(iOS)
import SwiftUI
import UIKit
#endif

/// How the pages are set: the type's size, and which way round ink and paper are.
public struct BookStyle: Equatable, Sendable {
    public var fontSize: Double
    public var inverted: Bool
    public init(fontSize: Double = 34, inverted: Bool = false) {
        self.fontSize = fontSize
        self.inverted = inverted
    }

    /// Light ink on black, which the glasses show as nothing; or dark ink on warm paper.
    public var ink: String { inverted ? "#1c1a17" : "#ece8e1" }
    public var paper: String { inverted ? "#f3eee4" : "#000000" }
}

/// The page script, the same on both phones: a chapter laid out in columns the height of the view,
/// one column a page, `columns` of them on a screen, and a screen turned by scrolling one view's
/// width. With the gap between columns twice the side margin, a screen's columns always land in
/// the same places.
public enum BookScripts {
    /// The margin round a page; the gap between two pages is twice it.
    public static let margin = 48
    /// Under the text, for the chapter and the percentage the glasses draw there.
    public static let footer = 34

    public static let page = """
    (function () {
      if (window.hudBook) return;
      var W = 1;
      function el(tag, id, parent) {
        var e = document.getElementById(id);
        if (!e) { e = document.createElement(tag); e.id = id; parent.appendChild(e); }
        return e;
      }
      // The page's own frame goes on as inline styles, which every WebKit applies.
      function set(e, css) {
        css.split(';').forEach(function (d) {
          var i = d.indexOf(':');
          if (i > 0) e.style.setProperty(d.slice(0, i).trim(), d.slice(i + 1).trim(), 'important');
        });
      }
      window.hudBook = {
        layout: function (o) {
          var root = document.documentElement;
          var head = document.head || root;
          var meta = el('meta', 'hud-book-viewport', head);
          meta.setAttribute('name', 'viewport');
          meta.setAttribute('content', 'width=device-width, initial-scale=1, user-scalable=no');
          W = window.innerWidth;
          // The page has not caught up with the view's new size yet: asked again in a moment.
          if (o.width && Math.abs(W - o.width) > 1) return -1;
          var m = o.margin, g = 2 * m;
          set(root, 'margin:0;padding:0;height:100vh;overflow:hidden;background:' + o.paper + ';-webkit-text-size-adjust:100%');
          set(document.body, 'margin:0;padding:' + m + 'px ' + m + 'px ' + (m + o.footer) + 'px;box-sizing:border-box;' +
            'width:100vw;height:100vh;max-width:none;column-count:' + o.columns + ';column-gap:' + g + 'px;' +
            'column-width:' + ((W - 2 * m - (o.columns - 1) * g) / o.columns) + 'px;' +
            'column-fill:auto;font-size:' + o.font + 'px;line-height:1.5;color:' + o.ink + ';background:transparent;' +
            'overflow:visible;font-family:Georgia,"Noto Serif",serif');
          el('style', 'hud-book-style', head).textContent =
            'body *{color:inherit!important;background-color:transparent!important;max-width:100%!important;}' +
            'img,svg,video,table{max-height:calc(100vh - ' + (2 * m + o.footer) + 'px)!important;' +
            'object-fit:contain;break-inside:avoid;}' +
            'p{orphans:2;widows:2;}' +
            'a{text-decoration:none!important;}';
          var end = el('span', 'hud-book-end', document.body || root);
          window.scrollTo(0, 0);
          void document.body.offsetHeight;
          var x = end.getBoundingClientRect().left + window.scrollX;
          return Math.max(1, Math.floor((x + 1) / W) + 1);
        },
        go: function (n) { window.scrollTo(n * W, 0); return n; }
      };
    })();
    """

    /// The call that lays the chapter out, answering how many screens it has.
    public static func layout(_ style: BookStyle, columns: Int, width: Double = 0) -> String {
        "hudBook.layout({font: \(style.fontSize), ink: '\(style.ink)', paper: '\(style.paper)', " +
            "columns: \(columns), margin: \(margin), footer: \(footer), width: \(width)})"
    }
}

/// The book open on the glasses: one web view, owned here, showing a chapter a screen at a time.
/// Turning past a chapter's last screen loads the next chapter; back past its first, the one
/// before, at its end. A change of type, of colours or of size lays the chapter out again, at the
/// same place in it.
@MainActor
public final class BookPager: NSObject, WKNavigationDelegate {
    public struct State: Equatable, Sendable {
        public var spine = 0
        public var screen = 0
        public var screens = 1
        /// Laid out and showing; false while a chapter loads.
        public var ready = false
    }

    public let webView: WKWebView
    public private(set) var state = State()
    public var onChange: ((State) -> Void)?
    public var style = BookStyle() {
        didSet { if style != oldValue { relayout() } }
    }
    /// One page a screen in the centre, two side by side when the reader fills the glasses.
    public var columns = 1 {
        didSet { if columns != oldValue { relayout() } }
    }

    private enum Landing { case fraction(Double), end }
    private var landing = Landing.fraction(0)
    private var folder: URL?
    private var epub: EPUB?
    private var generation = 0
    private var laidOutSize = CGSize.zero
    private var layoutRetries = 0

    public override init() {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 944, height: 952), configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
    }

    /// Where the book is, to keep.
    public var place: BookPlace {
        BookPlace(spine: state.spine, fraction: Double(state.screen) / Double(max(state.screens, 1)))
    }

    public func open(_ epub: EPUB, in folder: URL, at place: BookPlace) {
        self.epub = epub
        self.folder = folder
        load(min(max(place.spine, 0), epub.chapters.count - 1), landing: .fraction(place.fraction))
    }

    public func close() {
        epub = nil
        folder = nil
        generation += 1
        webView.loadHTMLString("", baseURL: nil)
        state = State()
        onChange?(state)
    }

    /// A page on (positive) or back, a screen at a time.
    public func turn(_ by: Int) {
        guard state.ready, let epub, by != 0 else { return }
        let target = state.screen + by
        if target >= state.screens {
            if state.spine + 1 < epub.chapters.count { load(state.spine + 1, landing: .fraction(0)) }
        } else if target < 0 {
            if state.spine > 0 { load(state.spine - 1, landing: .end) }
        } else {
            go(target)
        }
    }

    /// The view's size changed: the same place, laid out again.
    public func sizeChanged() {
        guard webView.bounds.size != laidOutSize, webView.bounds.width > 0 else { return }
        relayout()
    }

    private func load(_ spine: Int, landing: Landing) {
        guard let epub, let folder else { return }
        self.landing = landing
        generation += 1
        state.spine = spine
        state.ready = false
        webView.loadFileURL(folder.appendingPathComponent(epub.chapters[spine].path), allowingReadAccessTo: folder)
        onChange?(state)
    }

    private func relayout() {
        guard state.ready else { return }
        landing = .fraction(Double(state.screen) / Double(max(state.screens, 1)))
        layout()
    }

    private func layout() {
        let current = generation
        laidOutSize = webView.bounds.size
        // The script goes with every layout, rather than as a user script: it is there whatever
        // the page, and whenever it loaded.
        let width = Double(webView.bounds.width)
        webView.evaluateJavaScript(BookScripts.page + "\n" + BookScripts.layout(style, columns: columns, width: width)) { [weak self] result, _ in
            guard let self, current == self.generation else { return }
            if (result as? NSNumber)?.intValue == -1, self.layoutRetries < 40 {
                self.layoutRetries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self, current == self.generation else { return }
                    self.layout()
                }
                return
            }
            self.layoutRetries = 0
            let screens = max((result as? NSNumber)?.intValue ?? 1, 1)
            let screen: Int
            switch self.landing {
            case .end: screen = screens - 1
            case let .fraction(f): screen = min(max(Int((f * Double(screens)).rounded()), 0), screens - 1)
            }
            self.state.screens = screens
            self.state.ready = true
            self.go(screen)
        }
    }

    private func go(_ screen: Int) {
        state.screen = screen
        webView.evaluateJavaScript("hudBook.go(\(screen))", completionHandler: nil)
        onChange?(state)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard epub != nil else { return }
        layout()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard epub != nil else { return }
        layout()
    }
}

#if os(iOS)
/// The book's pages in their place on the glasses.
public struct BookPageView: UIViewRepresentable {
    public let pager: BookPager
    public let columns: Int

    public init(pager: BookPager, columns: Int) {
        self.pager = pager
        self.columns = columns
    }

    public func makeUIView(context: Context) -> Host { Host() }

    public func updateUIView(_ host: Host, context: Context) {
        host.pager = pager
        host.show(pager.webView)
        if pager.columns != columns {
            let pager = pager, columns = columns
            DispatchQueue.main.async { pager.columns = columns }
        }
    }

    public final class Host: UIView {
        weak var pager: BookPager?
        private weak var shown: UIView?

        func show(_ view: UIView) {
            guard shown !== view else { return }
            view.removeFromSuperview()
            addSubview(view)
            shown = view
            setNeedsLayout()
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            shown?.frame = bounds
            pager?.sizeChanged()
        }
    }
}
#endif
