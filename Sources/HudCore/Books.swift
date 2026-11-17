import Foundation
import ZIPFoundation

// Books: EPUBs read on the glasses. A book is a zip of XHTML chapters, listed in order by its
// package file (the "spine"); each chapter is laid out by WebKit in columns, one column a page
// (see `BookPager`). Here is everything about a book that is not drawing: opening the zip,
// reading the package, the shelf of books on the phone, and where each one was left.

/// A book on the shelf, as the phone lists it.
public struct BookInfo: Sendable, Equatable, Hashable, Codable {
    public var id: String
    public var title: String
    public var author: String
    public init(id: String, title: String, author: String) {
        self.id = id
        self.title = title
        self.author = author
    }
}

/// Where a book was left: the chapter, and how far through it.
public struct BookPlace: Sendable, Equatable, Codable {
    public var spine: Int
    /// 0 at the chapter's first page; the page shown is the one this falls on.
    public var fraction: Double
    public init(spine: Int = 0, fraction: Double = 0) {
        self.spine = spine
        self.fraction = fraction
    }
}

extension HudSnapshot {
    /// The reader: the shelf, the book open, and how it is set.
    public struct Books: Sendable, Equatable {
        public var library: [BookInfo] = []
        public var open: BookInfo?
        public var chapter: String = ""
        /// The screen shown in this chapter (one page, or two side by side), and how many it has.
        public var screen: Int = 0
        public var screens: Int = 1
        /// Through the whole book, 0 to 1.
        public var progress: Double = 0
        public var fontSize: Double = 34
        /// Dark ink on light paper, rather than light ink on the glasses' black.
        public var inverted = false
        /// How much of the world shows through the page: 0 is solid.
        public var transparency: Double = 0
        /// "COULDN'T OPEN THAT BOOK", for a few seconds.
        public var notice: String = ""
        public init() {}

        public static let fontSizes: [Double] = [22, 26, 30, 34, 40, 46, 54, 64]
        public static let transparencies: [Double] = [0, 0.25, 0.5, 0.75]

        /// The next size up (positive) or down.
        public func fontSize(stepping by: Int) -> Double {
            let sizes = Self.fontSizes
            let nearest = sizes.indices.min { abs(sizes[$0] - fontSize) < abs(sizes[$1] - fontSize) } ?? 3
            return sizes[min(max(nearest + by, 0), sizes.count - 1)]
        }

        /// Solid, then a quarter, half and three quarters see-through, then solid again.
        public var nextTransparency: Double {
            let steps = Self.transparencies
            let i = steps.firstIndex { $0 > transparency + 0.01 } ?? 0
            return steps[i]
        }

        public var percent: String { "\(Int((progress * 100).rounded(.down)))%" }

        public static let preview: Books = {
            var b = Books()
            let book = BookInfo(id: "preview", title: "The Lighthouse Keeper", author: "M. Arden")
            b.library = [book, BookInfo(id: "b", title: "Salt and Iron", author: "R. Okafor"),
                         BookInfo(id: "c", title: "A Field Guide to Small Hours", author: "J. Lind")]
            b.open = book
            b.chapter = "III. The Keeper's Log"
            b.screen = 4
            b.screens = 12
            b.progress = 0.37
            return b
        }()
    }
}

public enum BooksAction: Sendable, Equatable {
    /// A page on (positive) or back; two at a time where two are shown.
    case turn(Int)
    /// The type a size up or down.
    case font(Int)
    case invert
    /// The next step of see-through.
    case transparency
    case open(String)
    /// Choose an EPUB on the phone to put on the shelf.
    case add
    case remove(String)
}

// MARK: - The EPUB package

public struct EPUB: Sendable, Equatable {
    public struct Chapter: Sendable, Equatable {
        /// Relative to the book's folder.
        public var path: String
        public var bytes: Int
        /// The table of contents' name for it, or the last one before it.
        public var title: String
    }

    public var title: String
    public var author: String
    public var chapters: [Chapter]
    /// The cover picture, relative to the book's folder.
    public var cover: String?

    public enum Failure: Error { case notAnEPUB, noChapters }

    /// Unzips an .epub into a folder of its own.
    public static func unpack(_ file: URL, to folder: URL) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try manager.unzipItem(at: file, to: folder)
    }

    /// Reads an unzipped book: its container points at the package, which has the rest.
    public static func read(_ folder: URL) throws -> EPUB {
        let container = try XMLNode.parse(folder.appendingPathComponent("META-INF/container.xml"))
        guard let packagePath = container.first("rootfile")?.attributes["full-path"] else { throw Failure.notAnEPUB }
        let packageURL = folder.appendingPathComponent(packagePath)
        let package = try XMLNode.parse(packageURL)
        let base = packageURL.deletingLastPathComponent()

        func relative(_ href: String, from dir: URL) -> String {
            let clean = href.components(separatedBy: "#")[0]
            let decoded = clean.removingPercentEncoding ?? clean
            let url = URL(fileURLWithPath: decoded, relativeTo: dir).standardizedFileURL
            let root = folder.standardizedFileURL.path
            let path = url.path
            return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : decoded
        }

        let metadata = package.first("metadata")
        let title = metadata?.first("title")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = metadata?.first("creator")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        struct Item { var href: String; var type: String; var properties: String }
        var manifest: [String: Item] = [:]
        for item in package.first("manifest")?.all("item") ?? [] {
            guard let id = item.attributes["id"], let href = item.attributes["href"] else { continue }
            manifest[id] = Item(href: relative(href, from: base), type: item.attributes["media-type"] ?? "",
                                properties: item.attributes["properties"] ?? "")
        }

        // The cover: EPUB 3 marks the picture; EPUB 2 names it in a meta.
        var cover = manifest.values.first { $0.properties.split(separator: " ").contains("cover-image") }?.href
        if cover == nil, let id = metadata?.all("meta").first(where: { $0.attributes["name"] == "cover" })?
            .attributes["content"], let item = manifest[id], item.type.hasPrefix("image/") {
            cover = item.href
        }

        // Chapter names: EPUB 3's nav document, else EPUB 2's NCX.
        var names: [String: String] = [:]
        if let nav = manifest.values.first(where: { $0.properties.split(separator: " ").contains("nav") }),
           let doc = try? XMLNode.parse(folder.appendingPathComponent(nav.href)) {
            let dir = folder.appendingPathComponent(nav.href).deletingLastPathComponent()
            let toc = doc.all("nav").first { ($0.attributes["epub:type"] ?? $0.attributes["type"]) == "toc" }
                ?? doc.first("nav")
            for link in toc?.all("a") ?? [] {
                guard let href = link.attributes["href"] else { continue }
                let path = relative(href, from: dir)
                let name = link.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if names[path] == nil, !name.isEmpty { names[path] = name }
            }
        }
        if names.isEmpty, let ncx = manifest.values.first(where: { $0.type == "application/x-dtbncx+xml" }),
           let doc = try? XMLNode.parse(folder.appendingPathComponent(ncx.href)) {
            let dir = folder.appendingPathComponent(ncx.href).deletingLastPathComponent()
            for point in doc.all("navPoint") {
                guard let src = point.first("content")?.attributes["src"] else { continue }
                let path = relative(src, from: dir)
                let name = point.first("text")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if names[path] == nil, !name.isEmpty { names[path] = name }
            }
        }

        var chapters: [Chapter] = []
        var lastName = ""
        for ref in package.first("spine")?.all("itemref") ?? [] {
            guard ref.attributes["linear"] != "no", let id = ref.attributes["idref"], let item = manifest[id],
                  item.type.contains("html") else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(item.href).path)[.size]
                        as? Int) ?? 0
            if let name = names[item.href] { lastName = name }
            chapters.append(Chapter(path: item.href, bytes: max(size, 1), title: lastName))
        }
        guard !chapters.isEmpty else { throw Failure.noChapters }
        return EPUB(title: title.isEmpty ? "Untitled" : title, author: author, chapters: chapters, cover: cover)
    }

    /// How far through the book a place is, by the size of the chapters before it.
    public func progress(_ place: BookPlace) -> Double {
        let total = chapters.reduce(0) { $0 + $1.bytes }
        guard total > 0, chapters.indices.contains(place.spine) else { return 0 }
        let before = chapters[..<place.spine].reduce(0) { $0 + $1.bytes }
        return min(max((Double(before) + Double(chapters[place.spine].bytes) * place.fraction) / Double(total), 0), 1)
    }
}

/// Just enough XML: elements by local name, their attributes and their text.
final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var ownText = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    var text: String { ownText + children.map(\.text).joined() }

    func first(_ local: String) -> XMLNode? {
        for child in children {
            if child.name == local { return child }
            if let found = child.first(local) { return found }
        }
        return nil
    }

    func all(_ local: String) -> [XMLNode] {
        children.flatMap { ($0.name == local ? [$0] : []) + $0.all(local) }
    }

    static func parse(_ url: URL) throws -> XMLNode {
        let data = try Data(contentsOf: url)
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldResolveExternalEntities = false
        guard parser.parse() || !builder.root.children.isEmpty else { throw EPUB.Failure.notAnEPUB }
        return builder.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        let root = XMLNode(name: "", attributes: [:])
        private var stack: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            let node = XMLNode(name: local, attributes: attributes)
            (stack.last ?? root).children.append(node)
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.ownText += string
        }
    }
}

// MARK: - The shelf

/// The books on this phone: each unzipped in a folder of its own, listed (with where it was left)
/// in one small index, the last read first.
public final class BookLibrary {
    public let root: URL
    private struct Entry: Codable {
        var info: BookInfo
        var place: BookPlace
        /// The distant past for a book from the folder not yet read; those list by their file's name.
        var opened: Date
        var file: String?
    }
    private var entries: [Entry] = []
    private var cache: [String: EPUB] = [:]
    /// Files in the books folder already looked at (name, size, date), and books taken off the
    /// shelf, which the folder does not put back.
    private struct Seen: Codable {
        var files: Set<String> = []
        var removed: Set<String> = []
    }
    private var seen = Seen()

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: index), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved.filter { FileManager.default.fileExists(atPath: folder($0.info.id).path) }
        }
        if let data = try? Data(contentsOf: seenIndex), let saved = try? JSONDecoder().decode(Seen.self, from: data) {
            seen = saved
        }
    }

    private var seenIndex: URL { root.appendingPathComponent("seen.json") }

    /// Puts every .epub in a folder (and the folders in it) on the shelf, once: the phone's own
    /// Books folder, where books can be copied in from a computer or the Files app. Answers the
    /// books it added.
    @discardableResult
    public func scan(_ folder: URL) -> [BookInfo] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        var added: [BookInfo] = []
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "epub" }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        for file in files {
            let values = try? file.resourceValues(forKeys: Set(keys))
            let key = "\(file.lastPathComponent)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            guard !seen.files.contains(key) else { continue }
            seen.files.insert(key)
            guard let data = try? Data(contentsOf: file), !seen.removed.contains(Self.id(of: data)),
                  !entries.contains(where: { $0.info.id == Self.id(of: data) }) else { continue }
            if let book = try? add(file, fromFolder: true) { added.append(book) }
        }
        if let data = try? JSONEncoder().encode(seen) { try? data.write(to: seenIndex, options: .atomic) }
        return added
    }

    private var index: URL { root.appendingPathComponent("library.json") }

    /// The last read first; then the books from the folder not yet opened, by their file's name.
    public var books: [BookInfo] {
        entries.sorted {
            $0.opened != $1.opened ? $0.opened > $1.opened
                : ($0.file ?? "").localizedStandardCompare($1.file ?? "") == .orderedAscending
        }.map(\.info)
    }

    public func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

    /// Puts an .epub on the shelf. The same file twice is the same book.
    @discardableResult
    public func add(_ file: URL, fromFolder: Bool = false) throws -> BookInfo {
        let data = try Data(contentsOf: file)
        let id = Self.id(of: data)
        seen.removed.remove(id)
        if let existing = entries.first(where: { $0.info.id == id }) { return existing.info }
        let staged = root.appendingPathComponent("\(id).epub")
        try data.write(to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }
        do {
            try EPUB.unpack(staged, to: folder(id))
            let epub = try EPUB.read(folder(id))
            cache[id] = epub
            let info = BookInfo(id: id, title: epub.title, author: epub.author)
            entries.append(Entry(info: info, place: BookPlace(), opened: fromFolder ? .distantPast : Date(),
                                 file: fromFolder ? file.lastPathComponent : nil))
            save()
            return info
        } catch {
            try? FileManager.default.removeItem(at: folder(id))
            throw error
        }
    }

    public func remove(_ id: String) {
        seen.removed.insert(id)
        if let data = try? JSONEncoder().encode(seen) { try? data.write(to: seenIndex, options: .atomic) }
        entries.removeAll { $0.info.id == id }
        cache[id] = nil
        try? FileManager.default.removeItem(at: folder(id))
        save()
    }

    public func epub(_ id: String) -> EPUB? {
        if let cached = cache[id] { return cached }
        let epub = try? EPUB.read(folder(id))
        cache[id] = epub
        return epub
    }

    public func info(_ id: String) -> BookInfo? { entries.first { $0.info.id == id }?.info }

    public func place(_ id: String) -> BookPlace { entries.first { $0.info.id == id }?.place ?? BookPlace() }

    /// Where it is now, and that it was the last read.
    public func set(_ place: BookPlace, for id: String) {
        guard let i = entries.firstIndex(where: { $0.info.id == id }) else { return }
        entries[i].place = place
        entries[i].opened = Date()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: index, options: .atomic) }
    }

    /// The same everywhere for the same bytes: FNV-1a, 64 bits, in hex.
    static func id(of data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
