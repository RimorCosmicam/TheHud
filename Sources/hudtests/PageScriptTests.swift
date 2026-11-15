import Foundation
import WebKit
import AppKit
import HudCore

// The bridge script, run in real WebKit against a page with the kinds of top bars sites use.

@MainActor
func runPageScriptTests() {
    print("\nPageScripts.bridge (WebKit)")
    _ = NSApplication.shared

    let page = """
    <!doctype html><html><head><style>
      body { margin: 0; height: 4000px; }
      #header { position: fixed; top: 0; left: 0; right: 0; height: 56px; background: #222; }
      #guide { position: fixed; top: 56px; left: 0; width: 200px; height: 600px; }
      #sticky { position: sticky; top: 0; height: 40px; background: #333; }
      #box { height: 300px; overflow: auto; }
      #inner { position: sticky; top: 0; height: 20px; }
      #toast { position: fixed; bottom: 10px; left: 0; width: 100px; height: 30px; }
      #static { height: 30px; }
    </style></head><body>
      <div id="header"></div><div id="guide"></div>
      <div style="height: 200px"></div>
      <div id="sticky"></div>
      <div id="box"><div id="inner"></div><div style="height: 900px"></div></div>
      <div id="static"></div>
      <div id="toast"></div>
    </body></html>
    """

    let configuration = WKWebViewConfiguration()
    configuration.userContentController.addUserScript(
        WKUserScript(source: PageScripts.bridge(inset: 92), injectionTime: .atDocumentStart,
                     forMainFrameOnly: true))
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                            configuration: configuration)
    let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = webView

    final class Waiter: NSObject, WKNavigationDelegate {
        var done = false
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
    }
    let waiter = Waiter()
    webView.navigationDelegate = waiter
    webView.loadHTMLString(page, baseURL: nil)

    func spin(_ seconds: TimeInterval, until: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !until() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    func eval(_ js: String) -> String {
        var result = "?"
        var finished = false
        webView.evaluateJavaScript(js) { value, error in
            result = value.map { "\($0)" } ?? (error.map { "error: \($0)" } ?? "nil")
            finished = true
        }
        spin(5) { finished }
        return result
    }
    func top(_ id: String) -> String {
        eval("getComputedStyle(document.getElementById('\(id)')).top")
    }

    spin(10) { waiter.done }
    spin(0.6)

    test("a fixed header at the top moves below the bar") {
        expectEqual(top("header"), "92px")
    }
    test("a fixed bar under the header moves with it") {
        expectEqual(top("guide"), "148px")
    }
    test("bottom bars and ordinary content are left alone") {
        expectEqual(eval("document.getElementById('toast').hasAttribute('data-hud-top')"), "0")
        expectEqual(eval("document.getElementById('static').hasAttribute('data-hud-top')"), "0")
    }

    _ = eval("window.scrollTo(0, 260); 1")
    spin(0.8)

    test("a header that sticks to the page sticks below the bar") {
        expectEqual(top("sticky"), "92px")
    }
    test("a sticky header inside its own scrolling box is left alone") {
        expectEqual(eval("document.getElementById('inner').hasAttribute('data-hud-top')"), "0")
    }

    _ = eval("window.__hudSetTopInset(0); 1")
    test("fullscreen puts them all back") {
        expectEqual(top("header"), "0px")
        expectEqual(top("guide"), "56px")
    }
}
