package com.thehud.glasses

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoStories
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thehud.core.BookScripts
import com.thehud.core.HudSnapshot
import com.thehud.core.HudTheme

// The reader on the glasses, as BooksViews.swift draws it: the cover as a widget, one page in the
// centre, two side by side when it fills the glasses. The pages themselves are the device's (a web
// view); the stills draw a stand-in. Ink, paper and see-through are the same here and there.

private val HudSnapshot.Books.ink get() = if (inverted) Color(0xFF1C1A17) else Color(0xFFECE8E1)
private val HudSnapshot.Books.paper get() = if (inverted) Color(0xFFF3EEE4) else Color.Black

/** The cover, how far through, and the title; or how to get a book. */
@Composable
fun BooksWidget(books: HudSnapshot.Books, cover: ImageBitmap?) {
    val shape = RoundedCornerShape(HudTheme.CORNER.dp)
    Box(Modifier.fillMaxSize().clip(shape).background(HudTheme.surface).border(1.dp, HudTheme.edge, shape)) {
        val book = books.open
        if (book != null) {
            if (cover != null) Image(cover, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            else StandInCover(book.title, book.author)
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f))))
            Column(Modifier.align(Alignment.BottomStart).padding(22.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                BasicText(book.title, style = HudTheme.mont(22f), maxLines = 2)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BasicText(book.author.uppercase(), style = HudTheme.mont(14f, tracking = 2f, color = HudTheme.inkDim),
                        maxLines = 1, modifier = Modifier.weight(1f))
                    BasicText(books.percent, style = HudTheme.mont(16f, color = HudTheme.accent))
                }
                BoxWithConstraints(Modifier.fillMaxWidth().height(5.dp)) {
                    Box(Modifier.fillMaxSize().clip(RoundedCornerShape(3.dp)).background(Color.White.copy(alpha = 0.2f)))
                    Box(Modifier.width(maxWidth * books.progress.toFloat()).height(5.dp).clip(RoundedCornerShape(3.dp))
                        .background(HudTheme.accent))
                }
            }
        } else {
            Column(Modifier.fillMaxSize().padding(26.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Label("BOOKS")
                Spacer(Modifier.weight(1f))
                HudIcon(Icons.Rounded.AutoStories, 40f, HudTheme.accent)
                BasicText(if (books.library.isEmpty()) "Add an EPUB on the phone" else "Pick a book on the phone",
                    style = HudTheme.mont(20f, androidx.compose.ui.text.font.FontWeight.SemiBold, color = HudTheme.inkDim))
            }
        }
    }
}

/** A book with no cover picture: its title set on a plain board. */
@Composable
private fun StandInCover(title: String, author: String) {
    Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(HudTheme.accent.copy(alpha = 0.55f),
        HudTheme.accent.copy(alpha = 0.18f)))), contentAlignment = Alignment.Center) {
        Column(Modifier.padding(24.dp).offset(y = (-40).dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            BasicText(title, style = TextStyle(fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, fontSize = 30.sp,
                color = Color.White, textAlign = TextAlign.Center))
            Box(Modifier.width(40.dp).height(2.dp).background(Color.White.copy(alpha = 0.6f)))
            BasicText(author.uppercase(), style = HudTheme.mont(12f, tracking = 2.5f))
        }
    }
}

/**
 * The open book's pages: one, or two side by side, with the chapter and how far through in the
 * margin under them.
 */
@Composable
fun BookPages(books: HudSnapshot.Books, content: (@Composable (Int) -> Unit)?, standIn: Boolean, columns: Int, corner: Float) {
    val shape = RoundedCornerShape(corner.dp)
    if (books.open == null) return AppSurface {
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
            HudIcon(Icons.Rounded.AutoStories, 54f, HudTheme.accent)
            BasicText("NO BOOK OPEN", style = HudTheme.mont(28f, tracking = 3f))
            BasicText(if (books.library.isEmpty()) "Add an EPUB from the phone's pad" else "Pick one from the shelf on the phone",
                style = HudTheme.mont(22f, androidx.compose.ui.text.font.FontWeight.SemiBold, color = HudTheme.inkDim))
        }
    }
    Box(Modifier.fillMaxSize().clip(shape).alpha(1f - books.transparency.toFloat()).background(books.paper)) {
        if (content != null) content(columns) else if (standIn) StandInPages(books, columns)
        Row(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(start = BookScripts.MARGIN.dp,
            end = BookScripts.MARGIN.dp, bottom = 22.dp), verticalAlignment = Alignment.CenterVertically) {
            val style = HudTheme.mont(15f, tracking = 1.5f, color = books.ink.copy(alpha = 0.5f))
            BasicText(books.chapter, style = style, maxLines = 1, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(24.dp))
            if (books.notice.isNotEmpty()) {
                BasicText(books.notice, style = style.copy(color = HudTheme.accent), maxLines = 1)
                Spacer(Modifier.width(24.dp))
            }
            BasicText(books.percent, style = style)
        }
    }
}

/** The stills' pages: the sample's words, in the same margins and type. */
@Composable
private fun StandInPages(books: HudSnapshot.Books, columns: Int) {
    val m = BookScripts.MARGIN
    Row(Modifier.fillMaxSize().padding(start = m.dp, end = m.dp, top = m.dp, bottom = (m + BookScripts.FOOTER).dp),
        horizontalArrangement = Arrangement.spacedBy((2 * m).dp)) {
        repeat(columns) { column ->
            Column(Modifier.weight(1f).fillMaxSize().clipToBounds(),
                verticalArrangement = Arrangement.spacedBy((books.fontSize * 0.75).dp)) {
                repeat(3) { i ->
                    BasicText(BOOK_SAMPLE[(column * 2 + i) % BOOK_SAMPLE.size], style = TextStyle(fontFamily = FontFamily.Serif,
                        fontSize = books.fontSize.sp, lineHeight = (books.fontSize * 1.5).sp, color = books.ink))
                }
            }
        }
    }
}

/** Words for the stills, the iPhone's sample book's. */
private val BOOK_SAMPLE = listOf(
    "The lamp was lit at four, an hour before the light went out of the sky, because the keeper had learned that the sea liked to be warned early. He climbed the hundred and twelve steps with the oil can in one hand and the log under his arm, and at the top he wound the clockwork that turned the lens, and stood a while with his hand on the brass, feeling it begin to move.",
    "Below him the rocks were already in shadow. A gull sat on the gallery rail and watched him with one eye and then the other, the way gulls do when they have decided you are not food but have not decided what else you are. He told it the time, as he told everything the time, and wrote it in the log in the small square hand his father had used before him.",
    "In winter the boats came less often, and the island grew quiet in a way that was not silence. There was the wind, which had moods, and the sea, which had more of them, and the long low groan of the foghorn on the bad nights, which was the island's own voice and the only one it had.",
    "He kept a list of the ships he saw, their names when he could read them and their shapes when he could not. Some he saw every month for years, and he came to think of them as neighbours who never stopped to talk. When one of them stopped coming he would look for it for a season, and then cross it out, carefully, with a single line.",
    "The letter came in March, folded twice and smelling of the mainland. He read it standing in the doorway with the wind trying to take it from him, and then he read it again at the table with a cup of tea going cold beside it. It was short. Most of the letters that mattered were.",
)
