import Foundation
import WebKit
import AppKit
import HudCore

private func testThrows(_ name: String, _ body: () throws -> Void) {
    test(name) {
        do { try body() } catch { expect(false, "threw \(error)") }
    }
}

@MainActor
func runBookTests() {
    print("\nBooks")
    let manager = FileManager.default
    let work = manager.temporaryDirectory.appendingPathComponent("hud-books-\(UUID().uuidString)")
    defer { try? manager.removeItem(at: work) }
    let file = work.appendingPathComponent("sample.epub")
    try? manager.createDirectory(at: work, withIntermediateDirectories: true)

    testThrows("the sample is a real EPUB, read back: title, author, chapters in order, names, cover") {
        try BookSample.write(to: file, cover: Data([0x89, 0x50, 0x4E, 0x47]))
        let folder = work.appendingPathComponent("unpacked")
        try EPUB.unpack(file, to: folder)
        let epub = try EPUB.read(folder)
        expectEqual(epub.title, BookSample.title)
        expectEqual(epub.author, BookSample.author)
        expectEqual(epub.chapters.map(\.path), ["OEBPS/text/one.xhtml", "OEBPS/text/two.xhtml", "OEBPS/text/three end.xhtml"],
                    "the nav, marked not linear, is left out; escaped names are unescaped")
        expectEqual(epub.chapters.map(\.title), ["I. The Lamp", "II. Neighbours", "III. The Letter"],
                    "names from the nav, its #fragments ignored")
        expectEqual(epub.cover, "OEBPS/images/cover.png")
        expectEqual(epub.progress(BookPlace(spine: 0, fraction: 0)), 0)
        let midway = epub.progress(BookPlace(spine: 1, fraction: 0))
        expect(midway > 0.4 && midway < 0.7, "after the long first chapter: \(midway)")
    }

    testThrows("the shelf keeps books and where they were left, across opening it again") {
        let root = work.appendingPathComponent("shelf")
        let shelf = BookLibrary(root: root)
        let book = try shelf.add(file)
        expectEqual(try shelf.add(file).id, book.id, "the same file twice is one book")
        expectEqual(shelf.books.count, 1)
        shelf.set(BookPlace(spine: 2, fraction: 0.5), for: book.id)
        let again = BookLibrary(root: root)
        expectEqual(again.books, [book])
        expectEqual(again.place(book.id), BookPlace(spine: 2, fraction: 0.5))
        expect(again.epub(book.id) != nil)
        again.remove(book.id)
        expect(BookLibrary(root: root).books.isEmpty)
        expect(!manager.fileExists(atPath: again.folder(book.id).path))
    }

    testThrows("the books folder fills the shelf once, and a book taken off stays off") {
        let inbox = work.appendingPathComponent("inbox/sub")
        try manager.createDirectory(at: inbox, withIntermediateDirectories: true)
        try manager.copyItem(at: file, to: inbox.appendingPathComponent("a.epub"))
        try Data("x".utf8).write(to: inbox.appendingPathComponent("notes.txt"))
        let shelf = BookLibrary(root: work.appendingPathComponent("shelf3"))
        let added = shelf.scan(work.appendingPathComponent("inbox"))
        expectEqual(added.map(\.title), [BookSample.title])
        expect(shelf.scan(work.appendingPathComponent("inbox")).isEmpty, "seen already")
        shelf.remove(added[0].id)
        try manager.copyItem(at: file, to: inbox.appendingPathComponent("copy.epub"))
        expect(BookLibrary(root: work.appendingPathComponent("shelf3")).scan(work.appendingPathComponent("inbox")).isEmpty,
               "taken off the shelf, not put back by the folder")
        expectEqual(try shelf.add(file).title, BookSample.title, "added by hand, it comes back")
    }

    testThrows("not a book is refused, and leaves nothing behind") {
        let junk = work.appendingPathComponent("junk.epub")
        try Data("not a zip".utf8).write(to: junk)
        let shelf = BookLibrary(root: work.appendingPathComponent("shelf2"))
        expect((try? shelf.add(junk)) == nil)
        expect(shelf.books.isEmpty)
    }

    test("font sizes and see-through step as the pad does") {
        var b = HudSnapshot.Books()
        expectEqual(b.fontSize(stepping: 1), 40)
        expectEqual(b.fontSize(stepping: -1), 30)
        b.fontSize = 64
        expectEqual(b.fontSize(stepping: 1), 64)
        expectEqual(b.nextTransparency, 0.25)
        b.transparency = 0.75
        expectEqual(b.nextTransparency, 0)
    }

    // Pages, laid out by WebKit as the glasses do.
    _ = NSApplication.shared
    let shelf = BookLibrary(root: work.appendingPathComponent("pages"))
    guard let book = try? shelf.add(file), let epub = shelf.epub(book.id) else { return }
    let pager = BookPager()
    pager.webView.frame = CGRect(x: 0, y: 0, width: 944, height: 952)
    let window = NSWindow(contentRect: pager.webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = pager.webView
    func spin(until: () -> Bool) {
        let end = Date().addingTimeInterval(10)
        while Date() < end, !until() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    func settle() {
        spin { pager.state.ready }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
    func scrollX() -> Double {
        var x = -1.0
        pager.webView.evaluateJavaScript("window.scrollX") { v, _ in x = (v as? NSNumber)?.doubleValue ?? -2 }
        spin { x != -1 }
        return x
    }

    pager.open(epub, in: shelf.folder(book.id), at: BookPlace())
    settle()

    /// What the web view has, when a page count is not what it should be.
    func page() -> String {
        var s: String?
        pager.webView.evaluateJavaScript(
            "[location.href, document.body ? document.body.innerText.length : -1, window.innerWidth, window.innerHeight, " +
            "document.documentElement.scrollWidth, getComputedStyle(document.body).columnCount].join(' | ')") { v, e in
            s = (v as? String) ?? "error \(String(describing: e))"
        }
        spin { s != nil }
        var tried: String?
        pager.webView.evaluateJavaScript("try { " + BookScripts.page + "; String(" +
            BookScripts.layout(BookStyle(), columns: 1) + ") + ' ' + getComputedStyle(document.body).columnCount + ' ' + " +
            "document.getElementById('hud-book-style').namespaceURI } catch (e) { 'threw ' + e }") { v, e in
            tried = (v as? String) ?? "error \(String(describing: e))"
        }
        spin { tried != nil }
        return (s ?? "no answer") + " || again: " + (tried ?? "no answer")
    }

    test("a long chapter is several pages, and a page on scrolls one view across") {
        expect(pager.state.ready)
        expect(pager.state.screens > 2, "\(pager.state.screens) pages: \(page())")
        pager.turn(1)
        settle()
        expectEqual(pager.state.screen, 1)
        expectEqual(scrollX(), 944)
    }

    test("bigger type is more pages, at the same place") {
        let before = pager.state.screens
        pager.style.fontSize = 54
        settle()
        expect(pager.state.screens > before, "\(before) to \(pager.state.screens)")
        expect(pager.state.screen >= 1, "kept its place")
        pager.style.fontSize = 34
        settle()
    }

    test("two pages side by side halve the screens") {
        let one = pager.state.screens
        pager.webView.frame = CGRect(x: 0, y: 0, width: 1792, height: 952)
        pager.columns = 2
        settle()
        let two = pager.state.screens
        expect(two < one && two >= one / 2 - 1, "\(one) single, \(two) spreads")
        pager.columns = 1
        pager.webView.frame = CGRect(x: 0, y: 0, width: 944, height: 952)
        pager.sizeChanged()
        settle()
    }

    test("past a chapter's last page is the next chapter's first; back is the last page before") {
        pager.turn(pager.state.screens - pager.state.screen)
        settle()
        expectEqual(pager.state.spine, 1)
        expectEqual(pager.state.screen, 0)
        pager.turn(-1)
        settle()
        expectEqual(pager.state.spine, 0)
        expectEqual(pager.state.screen, pager.state.screens - 1)
        expectEqual(pager.place.spine, 0)
    }

    test("the place reopens where it was") {
        pager.open(epub, in: shelf.folder(book.id), at: BookPlace(spine: 2, fraction: 0.5))
        settle()
        expectEqual(pager.state.spine, 2)
        expectEqual(pager.state.screen, Int((0.5 * Double(pager.state.screens)).rounded()))
    }
}
