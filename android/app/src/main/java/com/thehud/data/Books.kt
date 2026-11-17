package com.thehud.data

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import com.thehud.core.BookInfo
import com.thehud.core.BookPlace
import com.thehud.core.BookScripts
import com.thehud.core.BookStyle
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.helpers.DefaultHandler
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.SAXParserFactory

// The reader on Android, as Books.swift and BookPager.swift on the iPhone: an EPUB unzipped and
// read, the shelf of them, and the web view that shows a chapter a screen at a time.

/** An unzipped book: its title, its author, its chapters in reading order, and its cover. */
data class EPUB(val title: String, val author: String, val chapters: List<Chapter>, val cover: String?) {
    /** A chapter: relative to the book's folder, its size, and the table of contents' name for it. */
    data class Chapter(val path: String, val bytes: Long, val title: String)

    class Failure(message: String) : Exception(message)

    /** How far through the book a place is, by the size of the chapters before it. */
    fun progress(place: BookPlace): Double {
        val total = chapters.sumOf { it.bytes }
        if (total <= 0 || place.spine !in chapters.indices) return 0.0
        val before = chapters.take(place.spine).sumOf { it.bytes }
        return ((before + chapters[place.spine].bytes * place.fraction) / total).coerceIn(0.0, 1.0)
    }

    companion object {
        /** Unzips an .epub into a folder of its own; nothing in it may land outside that folder. */
        fun unpack(input: InputStream, folder: File) {
            folder.deleteRecursively()
            folder.mkdirs()
            val root = folder.canonicalPath + File.separator
            ZipInputStream(input.buffered()).use { zip ->
                var any = false
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val out = File(folder, entry.name)
                    if (!out.canonicalPath.startsWith(root)) throw Failure("outside the book")
                    if (entry.isDirectory) out.mkdirs() else {
                        out.parentFile?.mkdirs()
                        out.outputStream().use { zip.copyTo(it) }
                        any = true
                    }
                }
                if (!any) throw Failure("not a zip")
            }
        }

        /** Reads an unzipped book: its container points at the package, which has the rest. */
        fun read(folder: File): EPUB {
            val container = XNode.parse(File(folder, "META-INF/container.xml"))
            val packagePath = container.first("rootfile")?.attributes?.get("full-path") ?: throw Failure("no package")
            val packageFile = File(folder, packagePath)
            val pkg = XNode.parse(packageFile)
            val base = packageFile.parentFile ?: folder
            val root = folder.canonicalPath + File.separator

            fun relative(href: String, dir: File): String {
                val decoded = percentDecode(href.substringBefore('#'))
                val path = File(dir, decoded).canonicalPath
                return if (path.startsWith(root)) path.removePrefix(root) else decoded
            }

            val metadata = pkg.first("metadata")
            val title = metadata?.first("title")?.text?.trim().orEmpty()
            val author = metadata?.first("creator")?.text?.trim().orEmpty()

            class Item(val href: String, val type: String, val properties: List<String>)
            val manifest = linkedMapOf<String, Item>()
            for (item in pkg.first("manifest")?.all("item").orEmpty()) {
                val id = item.attributes["id"] ?: continue
                val href = item.attributes["href"] ?: continue
                manifest[id] = Item(relative(href, base), item.attributes["media-type"].orEmpty(),
                    item.attributes["properties"].orEmpty().split(' ').filter { it.isNotEmpty() })
            }

            // The cover: EPUB 3 marks the picture; EPUB 2 names it in a meta.
            var cover = manifest.values.firstOrNull { "cover-image" in it.properties }?.href
            if (cover == null) {
                val id = metadata?.all("meta")?.firstOrNull { it.attributes["name"] == "cover" }?.attributes?.get("content")
                id?.let { manifest[it] }?.takeIf { it.type.startsWith("image/") }?.let { cover = it.href }
            }

            // Chapter names: EPUB 3's nav document, else EPUB 2's NCX.
            val names = mutableMapOf<String, String>()
            manifest.values.firstOrNull { "nav" in it.properties }?.let { nav ->
                val file = File(folder, nav.href)
                val doc = runCatching { XNode.parse(file) }.getOrNull() ?: return@let
                val toc = doc.all("nav").firstOrNull { (it.attributes["epub:type"] ?: it.attributes["type"]) == "toc" }
                    ?: doc.first("nav")
                for (link in toc?.all("a").orEmpty()) {
                    val href = link.attributes["href"] ?: continue
                    val name = link.text.trim()
                    if (name.isNotEmpty()) names.putIfAbsent(relative(href, file.parentFile ?: folder), name)
                }
            }
            if (names.isEmpty()) manifest.values.firstOrNull { it.type == "application/x-dtbncx+xml" }?.let { ncx ->
                val file = File(folder, ncx.href)
                val doc = runCatching { XNode.parse(file) }.getOrNull() ?: return@let
                for (point in doc.all("navPoint")) {
                    val src = point.first("content")?.attributes?.get("src") ?: continue
                    val name = point.first("text")?.text?.trim().orEmpty()
                    if (name.isNotEmpty()) names.putIfAbsent(relative(src, file.parentFile ?: folder), name)
                }
            }

            val chapters = mutableListOf<Chapter>()
            var lastName = ""
            for (ref in pkg.first("spine")?.all("itemref").orEmpty()) {
                if (ref.attributes["linear"] == "no") continue
                val item = ref.attributes["idref"]?.let { manifest[it] } ?: continue
                if (!item.type.contains("html")) continue
                names[item.href]?.let { lastName = it }
                chapters += Chapter(item.href, maxOf(File(folder, item.href).length(), 1), lastName)
            }
            if (chapters.isEmpty()) throw Failure("no chapters")
            return EPUB(title.ifEmpty { "Untitled" }, author, chapters, cover)
        }

        /** %20 and the like; a plus stays a plus, as in a path. */
        private fun percentDecode(s: String): String {
            if ('%' !in s) return s
            val out = ByteArrayOutputStream()
            var i = 0
            while (i < s.length) {
                val c = s[i]
                if (c == '%' && i + 2 < s.length && s.substring(i + 1, i + 3).toIntOrNull(16) != null) {
                    out.write(s.substring(i + 1, i + 3).toInt(16))
                    i += 3
                } else {
                    out.write(c.toString().toByteArray(Charsets.UTF_8))
                    i++
                }
            }
            return out.toString("UTF-8")
        }
    }
}

/** Just enough XML: elements by local name, their attributes and their text. */
class XNode(val name: String, val attributes: Map<String, String>) {
    val children = mutableListOf<XNode>()
    private val own = StringBuilder()

    val text: String get() = own.toString() + children.joinToString("") { it.text }

    fun first(local: String): XNode? {
        for (child in children) {
            if (child.name == local) return child
            child.first(local)?.let { return it }
        }
        return null
    }

    fun all(local: String): List<XNode> = children.flatMap { (if (it.name == local) listOf(it) else emptyList()) + it.all(local) }

    companion object {
        fun parse(file: File): XNode {
            val root = XNode("", emptyMap())
            val stack = ArrayDeque<XNode>()
            val handler = object : DefaultHandler() {
                override fun startElement(uri: String?, localName: String?, qName: String, attrs: Attributes) {
                    val map = HashMap<String, String>()
                    for (i in 0 until attrs.length) map[attrs.getQName(i)] = attrs.getValue(i)
                    val node = XNode(qName.substringAfterLast(':'), map)
                    (stack.lastOrNull() ?: root).children += node
                    stack.addLast(node)
                }
                override fun endElement(uri: String?, localName: String?, qName: String?) { stack.removeLastOrNull() }
                override fun characters(ch: CharArray, start: Int, length: Int) { stack.lastOrNull()?.own?.append(ch, start, length) }
                // A book's pages may name the XHTML DTD: it is never fetched.
                override fun resolveEntity(publicId: String?, systemId: String?) = InputSource(java.io.StringReader(""))
            }
            val factory = SAXParserFactory.newInstance().apply { isNamespaceAware = false; isValidating = false }
            runCatching { factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false) }
            val ok = runCatching { file.inputStream().use { factory.newSAXParser().parse(it, handler) } }.isSuccess
            if (!ok && root.children.isEmpty()) throw EPUB.Failure("not XML: ${file.name}")
            return root
        }
    }
}

/**
 * The books on this phone: each unzipped in a folder of its own, listed (with where it was left)
 * in one small index, the last read first. As the iPhone's BookLibrary, with the same ids.
 */
class BookLibrary(val root: File) {
    /** `opened` is 0 for a book from the folder not yet read; those list by their file's name, in order. */
    @Serializable private data class Entry(val info: BookInfo, val place: BookPlace, val opened: Double, val file: String = "")
    /** Files in the books folder already looked at (name, size, date), and books taken off the shelf. */
    @Serializable private data class Seen(val files: Set<String> = emptySet(), val removed: Set<String> = emptySet())

    private val json = Json { ignoreUnknownKeys = true }
    private var entries = mutableListOf<Entry>()
    private var seen = Seen()
    private val cache = mutableMapOf<String, EPUB>()
    private val index get() = File(root, "library.json")
    private val seenIndex get() = File(root, "seen.json")

    init {
        root.mkdirs()
        runCatching { json.decodeFromString<List<Entry>>(index.readText()) }.getOrNull()?.let { saved ->
            entries = saved.filter { folder(it.info.id).exists() }.toMutableList()
        }
        runCatching { json.decodeFromString<Seen>(seenIndex.readText()) }.getOrNull()?.let { seen = it }
    }

    /** The last read first; then the books from the folder not yet opened, by their file's name. */
    val books: List<BookInfo> get() = entries.sortedWith(compareByDescending<Entry> { it.opened }.thenBy { it.file.lowercase() })
        .map { it.info }

    fun folder(id: String) = File(root, id)

    /**
     * Puts every .epub in a folder (and the folders in it) on the shelf, once: the phone's own
     * Books folder, where books are copied in from a computer. Answers the books it added.
     */
    fun scan(folder: File): List<BookInfo> {
        val added = mutableListOf<BookInfo>()
        val files = folder.walkTopDown().filter { it.isFile && it.extension.equals("epub", ignoreCase = true) }
            .sortedBy { it.path.lowercase() }
        for (file in files) {
            val key = "${file.name}|${file.length()}|${file.lastModified() / 1000.0}"
            if (key in seen.files) continue
            seen = seen.copy(files = seen.files + key)
            val id = runCatching { file.inputStream().use(::idOf) }.getOrNull() ?: continue
            if (id in seen.removed || entries.any { it.info.id == id }) continue
            runCatching { file.inputStream().use { add(it, file.name) } }.getOrNull()?.let { added += it }
        }
        saveSeen()
        return added
    }

    /** Puts an .epub on the shelf. The same file twice is the same book. */
    fun add(input: InputStream, fromFolder: String? = null): BookInfo {
        root.mkdirs()
        val staged = File(root, "staging-${System.nanoTime()}.epub")
        try {
            staged.outputStream().use { input.copyTo(it) }
            val id = staged.inputStream().use(::idOf)
            if (id in seen.removed) { seen = seen.copy(removed = seen.removed - id); saveSeen() }
            entries.firstOrNull { it.info.id == id }?.let { return it.info }
            try {
                staged.inputStream().use { EPUB.unpack(it, folder(id)) }
                val epub = EPUB.read(folder(id))
                cache[id] = epub
                val info = BookInfo(id, epub.title, epub.author)
                entries += Entry(info, BookPlace(), if (fromFolder == null) now() else 0.0, fromFolder.orEmpty())
                save()
                return info
            } catch (e: Exception) {
                folder(id).deleteRecursively()
                throw e
            }
        } finally {
            staged.delete()
        }
    }

    fun remove(id: String) {
        seen = seen.copy(removed = seen.removed + id)
        saveSeen()
        entries.removeAll { it.info.id == id }
        cache.remove(id)
        folder(id).deleteRecursively()
        save()
    }

    fun epub(id: String): EPUB? = cache[id] ?: runCatching { EPUB.read(folder(id)) }.getOrNull()?.also { cache[id] = it }

    fun info(id: String) = entries.firstOrNull { it.info.id == id }?.info

    fun place(id: String) = entries.firstOrNull { it.info.id == id }?.place ?: BookPlace()

    /** Where it is now, and that it was the last read. */
    fun set(place: BookPlace, id: String) {
        val i = entries.indexOfFirst { it.info.id == id }
        if (i < 0) return
        entries[i] = entries[i].copy(place = place, opened = now())
        save()
    }

    private fun now() = System.currentTimeMillis() / 1000.0
    private fun save() { runCatching { index.writeText(json.encodeToString(entries.toList())) } }
    private fun saveSeen() { runCatching { seenIndex.writeText(json.encodeToString(seen)) } }

    companion object {
        /** The same on both phones for the same bytes: FNV-1a, 64 bits, in hex. */
        fun idOf(input: InputStream): String {
            var hash = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                for (i in 0 until n) {
                    hash = hash xor (buffer[i].toLong() and 0xff)
                    hash *= 0x100000001b3L
                }
            }
            return String.format(java.util.Locale.US, "%016x", hash)
        }
    }
}

/**
 * The book open on the glasses: one web view, owned here, showing a chapter a screen at a time.
 * Turning past a chapter's last screen loads the next chapter; back past its first, the one
 * before, at its end. A change of type, of colours or of size lays the chapter out again, at the
 * same place in it. As the iPhone's BookPager.
 */
@SuppressLint("SetJavaScriptEnabled")
class BookPager(context: Context) {
    data class State(val spine: Int = 0, val screen: Int = 0, val screens: Int = 1,
                     /** Laid out and showing; false while a chapter loads. */
                     val ready: Boolean = false)

    var state = State()
        private set
    var onChange: ((State) -> Unit)? = null
    var style = BookStyle()
        set(value) { if (field != value) { field = value; relayout() } }
    /** One page a screen in the centre, two side by side when the reader fills the glasses. */
    var columns = 1
        set(value) { if (field != value) { field = value; relayout() } }

    private sealed interface Landing { data class Fraction(val f: Double) : Landing; data object End : Landing }
    private var landing: Landing = Landing.Fraction(0.0)
    private var folder: File? = null
    private var epub: EPUB? = null
    private var generation = 0
    /** The chapter has loaded, and can be laid out once the view has a size. */
    private var loaded = false
    /** The view's width in the glasses' points, and its size in pixels, when last laid out. */
    private var points = 0f
    private var laidOut = Triple(0, 0, 0f)

    val view: WebView = WebView(context).apply {
        setBackgroundColor(Color.TRANSPARENT)
        settings.javaScriptEnabled = true
        settings.allowFileAccess = true
        settings.blockNetworkLoads = true
        settings.textZoom = 100
        settings.setSupportZoom(false)
        settings.useWideViewPort = false
        if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
            runCatching { WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, false) }
        }
        isVerticalScrollBarEnabled = false
        isHorizontalScrollBarEnabled = false
        overScrollMode = WebView.OVER_SCROLL_NEVER
        isFocusable = false
        webViewClient = object : WebViewClient() {
            // A link in a book goes nowhere: the pages turn from the pad.
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = true
            override fun onPageFinished(view: WebView, url: String?) {
                if (epub == null || url == null || !url.startsWith("file:")) return
                loaded = true
                layout()
            }
        }
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> post { sizeChanged() } }
    }

    /** Where the book is, to keep. */
    val place get() = BookPlace(state.spine, state.screen.toDouble() / maxOf(state.screens, 1))

    fun open(epub: EPUB, folder: File, place: BookPlace) {
        this.epub = epub
        this.folder = folder
        load(place.spine.coerceIn(0, epub.chapters.size - 1), Landing.Fraction(place.fraction))
    }

    fun close() {
        epub = null
        folder = null
        loaded = false
        generation++
        view.loadUrl("about:blank")
        state = State()
        onChange?.invoke(state)
    }

    /** A page on (positive) or back, a screen at a time. */
    fun turn(by: Int) {
        val epub = epub ?: return
        if (!state.ready || by == 0) return
        val target = state.screen + by
        when {
            target >= state.screens -> if (state.spine + 1 < epub.chapters.size) load(state.spine + 1, Landing.Fraction(0.0))
            target < 0 -> if (state.spine > 0) load(state.spine - 1, Landing.End)
            else -> go(target)
        }
    }

    /** Where the view is on the glasses: its width in their points. */
    fun place(points: Float) {
        this.points = points
        sizeChanged()
    }

    /** Takes the view out of whatever held it, to be put somewhere else. */
    fun detach() { (view.parent as? ViewGroup)?.removeView(view) }

    private fun sizeChanged() {
        if (view.width == 0 || Triple(view.width, view.height, points) == laidOut) return
        if (state.ready) relayout() else layout()
    }

    private fun load(spine: Int, landing: Landing) {
        val epub = epub ?: return
        val folder = folder ?: return
        this.landing = landing
        generation++
        loaded = false
        state = state.copy(spine = spine, ready = false)
        view.loadUrl(File(folder, epub.chapters[spine].path).toURI().toString())
        onChange?.invoke(state)
    }

    private fun relayout() {
        if (!state.ready) return
        landing = Landing.Fraction(state.screen.toDouble() / maxOf(state.screens, 1))
        layout()
    }

    private fun layout() {
        if (!loaded || view.width == 0) return
        val current = generation
        laidOut = Triple(view.width, view.height, points)
        view.evaluateJavascript(BookScripts.page + "\n" + BookScripts.layout(style, columns, points)) { result ->
            if (current != generation) return@evaluateJavascript
            val screens = maxOf(result?.trim('"')?.toDoubleOrNull()?.toInt() ?: 1, 1)
            val screen = when (val l = landing) {
                Landing.End -> screens - 1
                is Landing.Fraction -> Math.round(l.f * screens).toInt().coerceIn(0, screens - 1)
            }
            state = state.copy(screens = screens, ready = true)
            go(screen)
        }
    }

    private fun go(screen: Int) {
        state = state.copy(screen = screen)
        view.evaluateJavascript("hudBook.go($screen)", null)
        onChange?.invoke(state)
    }
}
