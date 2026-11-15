import Foundation
import CoreGraphics
import HudCore

// The glasses take no touches, so a click is the cursor's position checked against arithmetic.
// If this arithmetic and the drawn browser disagree, clicks land on the wrong thing.

func runLayoutTests() {
    print("\nGlassesLayout")

    let all = GlassesLayout()
    let frame = all.browserFrame!
    let bar = all.barFrame!

    test("browser sits right of the column, inside the safe inset") {
        expectEqual(frame.minX, HudTheme.safeInset + GlassesLayout.columnWidth + GlassesLayout.gap)
        expectEqual(frame.maxX, HudTheme.glassesSize.width - HudTheme.safeInset)
        expectEqual(frame.minY, HudTheme.safeInset)
    }

    test("browser takes the full width with the column off") {
        let alone = GlassesLayout(visible: [.browser]).browserFrame!
        expectEqual(alone.minX, HudTheme.safeInset)
    }

    test("no browser, no hits") {
        let glance = GlassesLayout(visible: [.clock, .map])
        expect(glance.browserFrame == nil)
        expectEqual(glance.hitTest(CGPoint(x: 960, y: 540)), .none)
    }

    test("the bar floats inside the panel") {
        expectEqual(bar.minX, frame.minX + BrowserMetrics.barInset)
        expectEqual(bar.minY, frame.minY + BrowserMetrics.barInset)
        expectEqual(bar.maxX, frame.maxX - BrowserMetrics.barInset)
    }

    test("bar: back, forward at the left end, reload at the right, title between") {
        let y = bar.midY
        let w = BrowserMetrics.buttonWidth
        expectEqual(all.hitTest(CGPoint(x: bar.minX + w / 2, y: y)), .back)
        expectEqual(all.hitTest(CGPoint(x: bar.minX + w * 1.5, y: y)), .forward)
        expectEqual(all.hitTest(CGPoint(x: bar.midX, y: y)), .address)
        expectEqual(all.hitTest(CGPoint(x: bar.maxX - 10, y: y)), .reload)
    }

    test("hover is the bar and only the bar") {
        expect(all.isOverBar(CGPoint(x: bar.midX, y: bar.midY)))
        expect(!all.isOverBar(CGPoint(x: bar.midX, y: bar.maxY + 4)))
        expect(!all.isOverBar(nil))
    }

    test("the page runs under the bar: clicks beside it reach the page") {
        // The margin above the bar is page, not chrome.
        expectEqual(all.hitTest(CGPoint(x: frame.minX + 4, y: frame.minY + 4)),
                    .page(CGPoint(x: 4, y: 4)))
        expectEqual(all.hitTest(CGPoint(x: frame.minX + 100, y: frame.minY + 300)),
                    .page(CGPoint(x: 100, y: 300)))
    }

    test("outside the browser is nothing") {
        expectEqual(all.hitTest(CGPoint(x: 100, y: 500)), .none)
    }

    print("\nAddressInput")

    test("hosts get https, schemes are kept, the rest is a search") {
        expectEqual(AddressInput.url(from: "apple.com")?.absoluteString, "https://apple.com")
        expectEqual(AddressInput.url(from: " http://a.b/c ")?.absoluteString, "http://a.b/c")
        let search = AddressInput.url(from: "xreal air specs")
        expectEqual(search?.host, "www.google.com", "spaces read as a Google search")
        expect(search?.absoluteString.contains("q=xreal%20air%20specs") == true)
        expect(AddressInput.url(from: "   ") == nil, "blank goes nowhere")
    }

    print("\nTextEdit")

    test("typing appends") {
        let edit = TextEdit.between("hel", "hello")
        expectEqual(edit.deletes, 0)
        expectEqual(edit.insert, "lo")
    }

    test("backspace deletes") {
        let edit = TextEdit.between("hello", "hell")
        expectEqual(edit.deletes, 1)
        expectEqual(edit.insert, "")
    }

    test("autocorrect replaces the word it changed") {
        let edit = TextEdit.between("I teh", "I the ")
        expectEqual(edit.deletes, 2)
        expectEqual(edit.insert, "he ")
    }

    test("emoji count as one character") {
        let edit = TextEdit.between("hi \u{1F44B}\u{1F3FD}", "hi ")
        expectEqual(edit.deletes, 1)
    }
}

func runHomePageTests() {
    print("\nHomePage")

    test("Google and YouTube by default") {
        expectEqual(Favorite.defaults.map(\.site), ["google.com", "youtube.com"])
    }

    test("a favourite is the site, not the page") {
        expectEqual(Favorite.site(of: "https://www.youtube.com/watch?v=abc"), "youtube.com")
        expectEqual(Favorite.site(of: "m.youtube.com"), "m.youtube.com")
    }

    test("every favourite becomes a link, and titles cannot break the page") {
        let html = HomePage.html([Favorite(title: "<b>Bad</b>", url: "https://a.example")]
                                 + Favorite.defaults)
        expect(html.contains("href=\"https://www.youtube.com\""))
        expect(html.contains("href=\"https://www.google.com\""))
        expect(html.contains("&lt;b&gt;Bad&lt;/b&gt;"))
        expect(!html.contains("<b>Bad</b>"))
    }
}
