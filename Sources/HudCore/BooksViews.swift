import SwiftUI

// The reader on the glasses: the cover as a widget, one page in the centre, two side by side
// when it fills the glasses. The pages themselves are the device's (`GlassesScreen.bookContent`,
// a web view); the stills draw a stand-in. Ink, paper and see-through are the same here and there.

extension HudSnapshot.Books {
    public var style: BookStyle { BookStyle(fontSize: fontSize, inverted: inverted) }
    var inkColor: Color { inverted ? Color(red: 0.11, green: 0.10, blue: 0.09) : Color(red: 0.93, green: 0.91, blue: 0.88) }
    var paperColor: Color { inverted ? Color(red: 0.953, green: 0.933, blue: 0.894) : .black }
}

/// The cover, how far through, and the title; or how to get a book.
public struct BooksWidget: View {
    var books: HudSnapshot.Books
    var cover: Image?
    public init(_ books: HudSnapshot.Books, cover: Image?) {
        self.books = books
        self.cover = cover
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let book = books.open {
                if let cover {
                    cover.resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                } else {
                    BookStandInCover(title: book.title, author: book.author)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title).font(HudTheme.mont(22, .black)).foregroundStyle(HudTheme.ink).lineLimit(2)
                    HStack {
                        Text(book.author.uppercased()).font(HudTheme.mont(14, .black)).tracking(2)
                            .foregroundStyle(HudTheme.inkDim).lineLimit(1)
                        Spacer()
                        Text(books.percent).font(HudTheme.mont(16, .black)).monospacedDigit()
                            .foregroundStyle(HudTheme.accent)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule().fill(HudTheme.accent).frame(width: g.size.width * books.progress)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(22)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetLabel(text: "BOOKS")
                    Spacer()
                    Image(systemName: "books.vertical").font(.system(size: 40, weight: .light))
                        .foregroundStyle(HudTheme.accent)
                    Text(books.library.isEmpty ? "Add an EPUB on the phone" : "Pick a book on the phone")
                        .font(HudTheme.mont(20, .semibold)).foregroundStyle(HudTheme.inkDim)
                }
                .padding(26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(HudTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
            .strokeBorder(HudTheme.edge, lineWidth: 1))
    }
}

/// A book with no cover picture: its title set on a plain board.
struct BookStandInCover: View {
    var title: String
    var author: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [HudTheme.accent.opacity(0.55), HudTheme.accent.opacity(0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Text(title).font(.custom("Georgia", size: 30)).italic().multilineTextAlignment(.center)
                Rectangle().fill(Color.white.opacity(0.6)).frame(width: 40, height: 2)
                Text(author.uppercased()).font(HudTheme.mont(12, .black)).tracking(2.5)
            }
            .foregroundStyle(.white)
            .padding(24)
            .offset(y: -40)
        }
    }
}

/// The open book's pages: one, or two side by side, with the chapter and how far through in the
/// margin under them.
public struct BookPages: View {
    var books: HudSnapshot.Books
    /// The live pages, laid out in this many columns.
    var content: ((Int) -> AnyView)?
    var standIn: Bool
    var columns: Int
    var corner: CGFloat

    public init(_ books: HudSnapshot.Books, content: ((Int) -> AnyView)?, standIn: Bool, columns: Int, corner: CGFloat) {
        self.books = books
        self.content = content
        self.standIn = standIn
        self.columns = columns
        self.corner = corner
    }

    public var body: some View {
        Group {
            if books.open == nil {
                noBook
            } else {
                ZStack(alignment: .bottom) {
                    books.paperColor
                    if let content {
                        content(columns)
                    } else if standIn {
                        BookStandInPages(books: books, columns: columns)
                    }
                    footer
                }
                .opacity(1 - books.transparency)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var footer: some View {
        let m = CGFloat(BookScripts.margin)
        return HStack {
            Text(books.chapter).lineLimit(1)
            Spacer(minLength: 24)
            if !books.notice.isEmpty {
                Text(books.notice).foregroundStyle(HudTheme.accent)
                Spacer(minLength: 24)
            }
            Text(books.percent).monospacedDigit()
        }
        .font(HudTheme.mont(15, .black)).tracking(1.5)
        .foregroundStyle(books.inkColor.opacity(0.5))
        .padding(.horizontal, m)
        .padding(.bottom, 22)
    }

    private var noBook: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical").font(.system(size: 54, weight: .light)).foregroundStyle(HudTheme.accent)
            Text("NO BOOK OPEN").font(HudTheme.mont(28, .black)).tracking(3).foregroundStyle(HudTheme.ink)
            Text(books.library.isEmpty ? "Add an EPUB from the phone's pad" : "Pick one from the shelf on the phone")
                .font(HudTheme.mont(22, .semibold)).foregroundStyle(HudTheme.inkDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appSurface()
    }
}

/// The stills' pages: the sample's words, in the same margins and type.
struct BookStandInPages: View {
    var books: HudSnapshot.Books
    var columns: Int
    var body: some View {
        let m = CGFloat(BookScripts.margin)
        HStack(alignment: .top, spacing: 2 * m) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: books.fontSize * 0.75) {
                    ForEach(0..<3, id: \.self) { i in
                        Text(BookSample.paragraphs[(column * 2 + i) % BookSample.paragraphs.count])
                            .font(.custom("Georgia", size: books.fontSize))
                            .lineSpacing(books.fontSize * 0.5)
                            .foregroundStyle(books.inkColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .padding(.top, m)
        .padding(.horizontal, m)
        .padding(.bottom, m + CGFloat(BookScripts.footer))
    }
}

// MARK: - The pad

/// Pages on and back, big; the type, the colours and the see-through; and the shelf, to open
/// another book or add one.
public struct BooksControls: View {
    public var books: HudSnapshot.Books
    public var action: (PhoneAction) -> Void
    @State private var shelf = false

    public init(books: HudSnapshot.Books, action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.books = books
        self.action = action
    }

    public var body: some View {
        if shelf || books.open == nil {
            shelfView
        } else {
            reading
        }
    }

    private var reading: some View {
        VStack(spacing: 10) {
            Button { shelf = true } label: {
                PadCard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(books.open?.title ?? "").font(HudTheme.mont(17, .black)).foregroundStyle(HudTheme.ink)
                                .lineLimit(1)
                            Text(books.notice.isEmpty ? "\(books.chapter.isEmpty ? "" : books.chapter + " \u{00B7} ")\(books.percent)"
                                 : books.notice)
                                .font(HudTheme.mont(12, .black)).tracking(1.2).foregroundStyle(HudTheme.inkDim).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "books.vertical").font(.system(size: 20, weight: .bold))
                            .foregroundStyle(HudTheme.inkDim)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                }
            }
            .buttonStyle(.plain)
            // Next is the one pressed most: the bigger target.
            GeometryReader { g in
                HStack(spacing: 10) {
                    PadButton(symbol: "chevron.left", title: "BACK", big: true) { action(.books(.turn(-1))) }
                        .frame(width: (g.size.width - 10) * 0.36)
                    PadButton(symbol: "chevron.right", title: "NEXT", big: true) { action(.books(.turn(1))) }
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                PadButton(symbol: "textformat.size.smaller", title: "SMALLER") { action(.books(.font(-1))) }
                PadButton(symbol: "textformat.size.larger", title: "LARGER") { action(.books(.font(1))) }
                PadButton(symbol: "circle.lefthalf.filled", title: books.inverted ? "DARK" : "PAPER",
                          lit: books.inverted) { action(.books(.invert)) }
                PadButton(symbol: "eye", title: books.transparency == 0 ? "SOLID" : "\(Int(books.transparency * 100))%",
                          lit: books.transparency > 0) { action(.books(.transparency)) }
            }
            .frame(height: 72)
        }
    }

    private var shelfView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("SHELF").font(HudTheme.mont(12, .black)).tracking(2).foregroundStyle(HudTheme.inkDim)
                Spacer()
                if books.open != nil {
                    Button("BACK TO THE BOOK") { shelf = false }
                        .font(HudTheme.mont(12, .black)).tracking(1.5).foregroundStyle(HudTheme.accent)
                }
            }
            .padding(.horizontal, 6)
            ScrollView {
                VStack(spacing: 8) {
                    if books.library.isEmpty {
                        Text("No books yet. Add an EPUB from Files.")
                            .font(HudTheme.mont(15, .semibold)).foregroundStyle(HudTheme.inkDim)
                            .padding(.vertical, 30)
                    }
                    ForEach(books.library, id: \.id) { book in
                        Button {
                            action(.books(.open(book.id)))
                            shelf = false
                        } label: {
                            PadCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(book.title).font(HudTheme.mont(16, .black)).foregroundStyle(HudTheme.ink)
                                            .lineLimit(1)
                                        Text(book.author).font(HudTheme.mont(12, .semibold))
                                            .foregroundStyle(HudTheme.inkDim).lineLimit(1)
                                    }
                                    Spacer()
                                    if book.id == books.open?.id {
                                        Image(systemName: "bookmark.fill").foregroundStyle(HudTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 18).padding(.vertical, 13)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { action(.books(.remove(book.id))) } label: {
                                Label("Remove from the shelf", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            PadButton(symbol: "plus", title: "ADD AN EPUB") { action(.books(.add)) }
                .frame(height: 64)
        }
    }
}
