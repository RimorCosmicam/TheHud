package com.thehud.core

import kotlinx.serialization.Serializable

// The reader's pieces both phones share, as Books.swift and BookPager.swift on the iPhone: a book
// on the shelf, where it was left, how its pages are set, and the script that sets them.

@Serializable
data class BookInfo(val id: String, val title: String, val author: String)

/** Where a book was left: a chapter (its place in the spine), and how far through it. */
@Serializable
data class BookPlace(val spine: Int = 0, val fraction: Double = 0.0)

/** How the pages are set: the type's size, and which way round ink and paper are. */
data class BookStyle(val fontSize: Double = 34.0, val inverted: Boolean = false) {
    /** Light ink on black, which the glasses show as nothing; or dark ink on warm paper. */
    val ink: String get() = if (inverted) "#1c1a17" else "#ece8e1"
    val paper: String get() = if (inverted) "#f3eee4" else "#000000"
}

/**
 * The page script, as the iPhone's: a chapter laid out in columns the height of the view, one
 * column a page, `columns` of them on a screen, and a screen turned by scrolling one view's width.
 * With the gap between columns twice the side margin, a screen's columns always land in the same
 * places. `points` is the view's width in the glasses' points: sizes are given in those, and the
 * script scales them to the web view's own pixels.
 */
object BookScripts {
    /** The margin round a page; the gap between two pages is twice it. */
    const val MARGIN = 48
    /** Under the text, for the chapter and the percentage the glasses draw there. */
    const val FOOTER = 34

    val page = """
    (function () {
      if (window.hudBook) return;
      var W = 1;
      function el(tag, id, parent) {
        var e = document.getElementById(id);
        if (!e) { e = document.createElement(tag); e.id = id; parent.appendChild(e); }
        return e;
      }
      window.hudBook = {
        layout: function (o) {
          var root = document.documentElement;
          var head = document.head || root;
          W = window.innerWidth;
          var k = o.points > 0 ? W / o.points : 1;
          var m = o.margin * k, g = 2 * m, f = o.footer * k;
          el('style', 'hud-book-style', head).textContent =
            'html{margin:0!important;padding:0!important;height:100vh!important;overflow:hidden!important;' +
            'background:' + o.paper + '!important;-webkit-text-size-adjust:100%!important;}' +
            'body{margin:0!important;padding:' + m + 'px ' + m + 'px ' + (m + f) + 'px!important;' +
            'box-sizing:border-box!important;width:100vw!important;height:100vh!important;max-width:none!important;' +
            'column-count:' + o.columns + '!important;column-gap:' + g + 'px!important;column-fill:auto!important;' +
            'font-size:' + (o.font * k) + 'px!important;line-height:1.5!important;color:' + o.ink + '!important;' +
            'background:transparent!important;overflow:visible!important;' +
            'font-family:Georgia,"Noto Serif",serif;}' +
            'body *{color:inherit!important;background-color:transparent!important;max-width:100%!important;}' +
            'img,svg,video,table{max-height:calc(100vh - ' + (2 * m + f) + 'px)!important;' +
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
    """.trimIndent()

    /** The call that lays the chapter out, answering how many screens it has. */
    fun layout(style: BookStyle, columns: Int, points: Float): String =
        "hudBook.layout({font: ${style.fontSize}, ink: '${style.ink}', paper: '${style.paper}', " +
            "columns: $columns, margin: $MARGIN, footer: $FOOTER, points: $points})"
}
