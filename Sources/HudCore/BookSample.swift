import Foundation
import ZIPFoundation

/// A small EPUB 3, written here, for the stills and the tests: three chapters, a nav document and
/// a cover, zipped as a real book is.
public enum BookSample {
    static let paragraphs = [
        "The lamp was lit at four, an hour before the light went out of the sky, because the keeper had learned that the sea liked to be warned early. He climbed the hundred and twelve steps with the oil can in one hand and the log under his arm, and at the top he wound the clockwork that turned the lens, and stood a while with his hand on the brass, feeling it begin to move.",
        "Below him the rocks were already in shadow. A gull sat on the gallery rail and watched him with one eye and then the other, the way gulls do when they have decided you are not food but have not decided what else you are. He told it the time, as he told everything the time, and wrote it in the log in the small square hand his father had used before him.",
        "In winter the boats came less often, and the island grew quiet in a way that was not silence. There was the wind, which had moods, and the sea, which had more of them, and the long low groan of the foghorn on the bad nights, which was the island's own voice and the only one it had.",
        "He kept a list of the ships he saw, their names when he could read them and their shapes when he could not. Some he saw every month for years, and he came to think of them as neighbours who never stopped to talk. When one of them stopped coming he would look for it for a season, and then cross it out, carefully, with a single line.",
        "The letter came in March, folded twice and smelling of the mainland. He read it standing in the doorway with the wind trying to take it from him, and then he read it again at the table with a cup of tea going cold beside it. It was short. Most of the letters that mattered were.",
    ]

    static func chapter(_ title: String, _ count: Int, offset: Int) -> String {
        let body = (0..<count).map { "<p>\(paragraphs[($0 + offset) % paragraphs.count])</p>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>\(title)</title></head>
        <body><h2>\(title)</h2>
        \(body)
        </body></html>
        """
    }

    public static let title = "The Lighthouse Keeper"
    public static let author = "M. Arden"

    /// Writes the book's .epub at `file`, with a cover from `cover` (PNG bytes) if given.
    public static func write(to file: URL, cover: Data? = nil) throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("book-sample-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: folder) }
        let files: [String: String] = [
            "META-INF/container.xml": """
            <?xml version="1.0"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """,
            "OEBPS/content.opf": """
            <?xml version="1.0" encoding="utf-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="id">thehud-sample</dc:identifier>
                <dc:title>\(title)</dc:title>
                <dc:creator>\(author)</dc:creator>
                <dc:language>en</dc:language>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="cover" href="images/cover.png" media-type="image/png" properties="cover-image"/>
                <item id="c1" href="text/one.xhtml" media-type="application/xhtml+xml"/>
                <item id="c2" href="text/two.xhtml" media-type="application/xhtml+xml"/>
                <item id="c3" href="text/three%20end.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="nav" linear="no"/>
                <itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/>
              </spine>
            </package>
            """,
            "OEBPS/nav.xhtml": """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <body><nav epub:type="toc"><ol>
              <li><a href="text/one.xhtml">I. The Lamp</a></li>
              <li><a href="text/two.xhtml#start">II. Neighbours</a></li>
              <li><a href="text/three%20end.xhtml">III. The Letter</a></li>
            </ol></nav></body></html>
            """,
            "OEBPS/text/one.xhtml": chapter("I. The Lamp", 14, offset: 0),
            "OEBPS/text/two.xhtml": chapter("II. Neighbours", 3, offset: 2),
            "OEBPS/text/three end.xhtml": chapter("III. The Letter", 9, offset: 4),
        ]
        for (path, text) in files {
            let url = folder.appendingPathComponent(path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try Data("application/epub+zip".utf8).write(to: folder.appendingPathComponent("mimetype"))
        if let cover {
            let url = folder.appendingPathComponent("OEBPS/images/cover.png")
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try cover.write(to: url)
        }
        try? manager.removeItem(at: file)
        try manager.zipItem(at: folder, to: file, shouldKeepParent: false)
    }
}
