package com.thehud

import com.thehud.core.BookPlace
import com.thehud.core.HudSnapshot
import com.thehud.data.BookLibrary
import com.thehud.data.EPUB
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** The reader's books, read and shelved without the glasses: as the iPhone's BookTests. */
class BookTest {
    @get:Rule val temp = TemporaryFolder()

    private fun sample(file: File, title: String = "The Lighthouse Keeper") {
        fun chapter(name: String, n: Int) = """<?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>$name</title></head>
            <body><h2>$name</h2>${"<p>Words&nbsp;and words.</p>".repeat(n)}</body></html>"""
        val files = mapOf(
            "mimetype" to "application/epub+zip",
            "META-INF/container.xml" to """<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""",
            "OEBPS/content.opf" to """<?xml version="1.0" encoding="utf-8"?>
                <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
                <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">x</dc:identifier>
                <dc:title>$title</dc:title><dc:creator>M. Arden</dc:creator></metadata>
                <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="cover" href="images/cover.png" media-type="image/png" properties="cover-image"/>
                <item id="c1" href="text/one.xhtml" media-type="application/xhtml+xml"/>
                <item id="c2" href="text/two.xhtml" media-type="application/xhtml+xml"/>
                <item id="c3" href="text/three%20end.xhtml" media-type="application/xhtml+xml"/></manifest>
                <spine><itemref idref="nav" linear="no"/><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/></spine></package>""",
            "OEBPS/nav.xhtml" to """<?xml version="1.0" encoding="utf-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
                <nav epub:type="toc"><ol><li><a href="text/one.xhtml">I. The Lamp</a></li>
                <li><a href="text/three%20end.xhtml#x">III. The Letter</a></li></ol></nav></body></html>""",
            "OEBPS/text/one.xhtml" to chapter("I", 30),
            "OEBPS/text/two.xhtml" to chapter("II", 10),
            "OEBPS/text/three end.xhtml" to chapter("III", 20),
        )
        ZipOutputStream(file.outputStream()).use { zip ->
            for ((path, text) in files) { zip.putNextEntry(ZipEntry(path)); zip.write(text.toByteArray()); zip.closeEntry() }
        }
    }

    @Test fun readsTheBook() {
        val file = temp.newFile("a.epub")
        sample(file)
        val folder = temp.newFolder("a")
        file.inputStream().use { EPUB.unpack(it, folder) }
        val epub = EPUB.read(folder)
        assertEquals("The Lighthouse Keeper", epub.title)
        assertEquals("M. Arden", epub.author)
        // The nav is not read in line; a chapter with no name of its own takes the last one's.
        assertEquals(listOf("OEBPS/text/one.xhtml", "OEBPS/text/two.xhtml", "OEBPS/text/three end.xhtml"), epub.chapters.map { it.path })
        assertEquals(listOf("I. The Lamp", "I. The Lamp", "III. The Letter"), epub.chapters.map { it.title })
        assertEquals("OEBPS/images/cover.png", epub.cover)
        assertEquals(0.0, epub.progress(BookPlace(0, 0.0)), 1e-9)
        assertTrue(epub.progress(BookPlace(2, 0.5)) in 0.6..0.95)
    }

    @Test fun theShelfKeepsPlacesAndTheFolderAddsOnce() {
        val inbox = temp.newFolder("inbox")
        sample(File(inbox, "02 - Second.epub"), "Second")
        sample(File(inbox, "01 - First.epub"), "First")
        File(inbox, "junk.epub").writeText("not a book")
        val root = temp.newFolder("shelf")
        val shelf = BookLibrary(root)
        val added = shelf.scan(inbox)
        // In the files' order, and the junk refused.
        assertEquals(listOf("First", "Second"), added.map { it.title })
        assertEquals(listOf("First", "Second"), shelf.books.map { it.title })
        assertTrue(shelf.scan(inbox).isEmpty())
        val second = added[1].id
        shelf.set(BookPlace(1, 0.25), second)
        // Read last: first on the shelf; and kept.
        val again = BookLibrary(root)
        assertEquals(listOf("Second", "First"), again.books.map { it.title })
        assertEquals(BookPlace(1, 0.25), again.place(second))
        // Taken off the shelf, the folder does not put it back.
        again.remove(second)
        File(inbox, "02 - Second.epub").setLastModified(1_000_000)
        assertTrue(again.scan(inbox).isEmpty())
        assertNull(again.info(second))
    }

    @Test fun theSameIdsAsTheIPhone() {
        // FNV-1a 64 of "a", as Swift's BookLibrary.id(of:).
        assertEquals("af63dc4c8601ec8c", BookLibrary.idOf("a".byteInputStream()))
    }

    @Test fun typeAndSeeThroughStep() {
        val b = HudSnapshot.Books()
        assertEquals(40.0, b.fontSize(1), 0.0)
        assertEquals(64.0, b.copy(fontSize = 64.0).fontSize(1), 0.0)
        assertEquals(0.25, b.nextTransparency, 0.0)
        assertEquals(0.0, b.copy(transparency = 0.75).nextTransparency, 0.0)
        assertEquals("37%", HudSnapshot.Books.preview.percent)
    }

    @Test fun everyBookInTheFolderReads() {
        val dir = System.getenv("HUD_BOOKS") ?: return
        val failed = File(dir).listFiles { f -> f.extension == "epub" }!!.sorted().mapNotNull { f ->
            val folder = temp.newFolder()
            runCatching { f.inputStream().use { EPUB.unpack(it, folder) }; EPUB.read(folder) }
                .onSuccess { println("${f.name}: ${it.title} / ${it.author} / ${it.chapters.size} chapters / cover ${it.cover}") }
                .exceptionOrNull()?.let { "${f.name}: $it" }
        }
        assertEquals(emptyList<String>(), failed)
    }
}
