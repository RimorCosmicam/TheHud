import Foundation
import CoreGraphics
import HudCore

// The glasses take no touches, so a click is the cursor's position checked against arithmetic.
// If this arithmetic and the drawn browser disagree, clicks land on the wrong thing.

func runLayoutTests() {
    print("\nGlassesLayout")

    let all = GlassesLayout()
    let frame = all.browserFrame!
    let addressY = frame.minY + BrowserMetrics.tabHeight + BrowserMetrics.addressHeight / 2

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

    test("address row: back, forward, field, reload") {
        let left = frame.minX + BrowserMetrics.sidePadding
        let nav = BrowserMetrics.navButtonWidth
        expectEqual(all.hitTest(CGPoint(x: left + nav / 2, y: addressY)), .back)
        expectEqual(all.hitTest(CGPoint(x: left + nav * 1.5, y: addressY)), .forward)
        expectEqual(all.hitTest(CGPoint(x: frame.midX, y: addressY)), .address)
        expectEqual(all.hitTest(CGPoint(x: frame.maxX - BrowserMetrics.sidePadding - 10,
                                        y: addressY)), .reload)
    }

    test("tabs strip is inert") {
        expectEqual(all.hitTest(CGPoint(x: frame.midX, y: frame.minY + 10)), .none)
    }

    test("page clicks arrive in the web view's own coordinates") {
        let content = all.contentFrame!
        let hit = all.hitTest(CGPoint(x: content.minX + 100, y: content.minY + 40))
        expectEqual(hit, .page(CGPoint(x: 100, y: 40)))
    }

    test("outside the browser is nothing") {
        expectEqual(all.hitTest(CGPoint(x: 100, y: 500)), .none)
    }

    print("\nAddressInput")

    test("hosts get https, schemes are kept, the rest is a search") {
        expectEqual(AddressInput.url(from: "apple.com")?.absoluteString, "https://apple.com")
        expectEqual(AddressInput.url(from: " http://a.b/c ")?.absoluteString, "http://a.b/c")
        let search = AddressInput.url(from: "xreal air specs")
        expect(search?.host?.contains("duckduckgo") == true, "spaces read as a search")
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
