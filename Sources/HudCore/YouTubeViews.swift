import SwiftUI

// YouTube on the glasses, drawn in the HUD's own hand. The video itself is a web view of its
// own (see `YouTubePlayer`) showing nothing but the picture; the lists, buttons and titles
// around it are ours, read from YouTube's pages with the wearer's own sign-in.

// MARK: - Layout

/// Where everything sits in the app held up alone, in the safe frame's points (1792 by 952),
/// so clicks can be worked out from the cursor.
public enum YouTubeAppLayout {
    public enum Target: Equatable, Sendable {
        case tab(HudSnapshot.YouTube.Tab)
        case nowPlaying
        /// A card in the browse grid, by its index in the tab's list.
        case card(Int)
        /// Watching: the video is the whole canvas, and a click pauses it.
        case video
    }

    public static let size = CGSize(width: 1792, height: 952)

    // Browse.
    public static let columns = 4
    public static let visibleRows = 2
    static let gridX: CGFloat = 72
    static let gridY: CGFloat = 150
    static let cardWidth: CGFloat = 388
    static let cardGap: CGFloat = 32
    static let thumbHeight: CGFloat = 218
    static let cardHeight: CGFloat = 330
    static let rowGap: CGFloat = 34
    public static let nowPlayingTile = CGRect(x: 1240, y: 34, width: 480, height: 84)
    /// The video in the tile.
    public static let tileVideo = CGRect(x: 1242, y: 36, width: 142, height: 80)

    // The same app at other sizes, as the centre app: as many columns as fit, and the tile under
    // the tabs when there is no room beside them.
    static func wide(_ size: CGSize) -> Bool { size.width >= 1400 }
    public static func columns(_ size: CGSize) -> Int { wide(size) ? columns : 2 }
    public static func visibleRows(_ size: CGSize) -> Int { size.height >= 900 ? visibleRows : 1 }
    static func gridTop(_ size: CGSize) -> CGFloat { wide(size) ? gridY : gridY + 100 }

    public static func nowPlayingTile(in size: CGSize) -> CGRect {
        if size == Self.size { return nowPlayingTile }
        return wide(size) ? CGRect(x: size.width - 72 - 480, y: 34, width: 480, height: 84)
            : CGRect(x: 72, y: 128, width: size.width - 144, height: 84)
    }

    public static func tileVideo(in size: CGSize) -> CGRect {
        let tile = nowPlayingTile(in: size)
        return CGRect(x: tile.minX + 2, y: tile.minY + 2, width: 142, height: 80)
    }

    public static func cardFrame(slot: Int, in size: CGSize) -> CGRect {
        if size == Self.size { return cardFrame(slot: slot) }
        let cols = columns(size)
        let width = (size.width - gridX * 2 - cardGap * CGFloat(cols - 1)) / CGFloat(cols)
        let height = min(cardHeight, width * thumbHeight / cardWidth + 112)
        return CGRect(x: gridX + CGFloat(slot % cols) * (width + cardGap),
                      y: gridTop(size) + CGFloat(slot / cols) * (height + rowGap), width: width, height: height)
    }

    /// Watching in the centre: the video as large as fits, with its title under it.
    public static func centreVideo(in size: CGSize) -> CGRect {
        let width = min(size.width - 64, (size.height - 200) * 16 / 9)
        return CGRect(x: (size.width - width) / 2, y: 32, width: width, height: width * 9 / 16)
    }

    public static func target(at point: CGPoint, _ youtube: HudSnapshot.YouTube, in size: CGSize) -> Target? {
        if size == Self.size { return target(at: point, youtube) }
        switch youtube.page {
        case .browse:
            for (i, tab) in youtube.tabs.enumerated() where tabFrame(i, of: youtube.tabs).contains(point) {
                return .tab(tab)
            }
            if youtube.hasVideo, nowPlayingTile(in: size).contains(point) { return .nowPlaying }
            let list = youtube.list(youtube.tab)
            let cols = columns(size)
            for slot in 0..<(cols * visibleRows(size)) where cardFrame(slot: slot, in: size).contains(point) {
                let index = youtube.scrollRow * cols + slot
                return list.indices.contains(index) ? .card(index) : nil
            }
            return nil
        case .player:
            return .video
        }
    }

    public static func maxRow(_ count: Int, in size: CGSize) -> Int {
        let cols = columns(size)
        return max(0, (count + cols - 1) / cols - visibleRows(size))
    }

    public static func tabFrame(_ index: Int, of tabs: [HudSnapshot.YouTube.Tab]) -> CGRect {
        var x: CGFloat = 72
        for (i, tab) in tabs.enumerated() {
            let width = tabWidth(tab)
            if i == index { return CGRect(x: x, y: 44, width: width, height: 60) }
            x += width + 14
        }
        return .zero
    }

    static func tabWidth(_ tab: HudSnapshot.YouTube.Tab) -> CGFloat {
        switch tab {
        case .home: 150
        case .subscriptions: 290
        case .search: 180
        }
    }

    /// The card at a place in the grid, counting from the first row shown.
    public static func cardFrame(slot: Int) -> CGRect {
        let column = slot % columns, row = slot / columns
        return CGRect(x: gridX + CGFloat(column) * (cardWidth + cardGap),
                      y: gridY + CGFloat(row) * (cardHeight + rowGap),
                      width: cardWidth, height: cardHeight)
    }

    public static func target(at point: CGPoint, _ youtube: HudSnapshot.YouTube) -> Target? {
        switch youtube.page {
        case .browse:
            for (i, tab) in youtube.tabs.enumerated() where tabFrame(i, of: youtube.tabs).contains(point) {
                return .tab(tab)
            }
            if youtube.hasVideo, nowPlayingTile.contains(point) { return .nowPlaying }
            let list = youtube.list(youtube.tab)
            for slot in 0..<(columns * visibleRows) where cardFrame(slot: slot).contains(point) {
                let index = youtube.scrollRow * columns + slot
                return list.indices.contains(index) ? .card(index) : nil
            }
            return nil
        case .player:
            return .video
        }
    }

    /// The last first-row the grid can scroll to.
    public static func maxRow(_ count: Int) -> Int {
        max(0, (count + columns - 1) / columns - visibleRows)
    }
}

// MARK: - The widget

/// In a slot: the video alone, filling it, with what it is and how far along underneath.
public struct YouTubeWidget: View {
    public var youtube: HudSnapshot.YouTube
    /// The live video is drawn underneath, by `YouTubeVideoLayer`; leave its place clear.
    public var live: Bool
    public var standIn: Bool

    public init(_ youtube: HudSnapshot.YouTube, live: Bool = false, standIn: Bool = false) {
        self.youtube = youtube
        self.live = live
        self.standIn = standIn
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            live && youtube.hasVideo ? Color.clear : Color.black
            if youtube.hasVideo {
                PlayerFrame(live: live, standIn: standIn)
                VStack(alignment: .leading, spacing: 8) {
                    Text(youtube.isAd ? "AD" : youtube.title).font(HudTheme.mont(18, .black))
                        .foregroundStyle(youtube.isAd ? HudTheme.accent : HudTheme.ink)
                        .lineLimit(1)
                    if !youtube.isLive { ProgressLine(progress: youtube.progress).frame(height: 4) }
                }
                .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 18)
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)],
                                           startPoint: .top, endPoint: .bottom))
                if !youtube.notice.isEmpty {
                    Text(youtube.notice).font(HudTheme.mont(16, .semibold)).foregroundStyle(HudTheme.inkDim)
                        .multilineTextAlignment(.center).padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !youtube.isPlaying {
                    Image(systemName: "pause.fill").font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetLabel(text: "YOUTUBE")
                    Text("Hold to open and pick something")
                        .font(HudTheme.mont(18, .semibold)).foregroundStyle(HudTheme.inkFaint)
                }
                .padding(26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
            .strokeBorder(HudTheme.edge, lineWidth: 1))
    }
}

/// Where the video goes in a view: clear when the live video is underneath, a stand-in for
/// stills.
struct PlayerFrame: View {
    var live: Bool
    var standIn: Bool

    var body: some View {
        if live {
            Color.clear
        } else {
            GeometryReader { geometry in
                let size = YouTubeVideoLayer.fit(geometry.size)
                ZStack {
                    Color.black
                    if standIn { StandInFrame().frame(width: size.width, height: size.height) }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}

/// The one live video on the glasses. It is never moved from view to view, only resized and
/// placed: WebKit loses the picture of a playing video when its web view is taken out of the
/// window and put back, so the slot, the tile and the whole canvas are all this same layer,
/// with the widget and the app drawn over it and clear where it shows.
public struct YouTubeVideoLayer: View {
    public var content: AnyView
    /// The box it is clipped to, in canvas points; nil keeps it off the canvas, still playing.
    public var box: CGRect?
    public var corner: CGFloat

    public init(content: AnyView, box: CGRect?, corner: CGFloat) {
        self.content = content
        self.box = box
        self.corner = corner
    }

    /// 16:9, as large as fits.
    static func fit(_ size: CGSize) -> CGSize {
        let scale = min(size.width / 16, size.height / 9)
        return CGSize(width: 16 * scale, height: 9 * scale)
    }

    public var body: some View {
        // Off the canvas it is still in the window, so it keeps its picture for coming back.
        let box = self.box ?? CGRect(x: -1400, y: 0, width: 1280, height: 720)
        let video = Self.fit(box.size)
        ZStack {
            Color.black
            content.frame(width: video.width, height: video.height)
        }
        .frame(width: box.width, height: box.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .offset(x: box.minX, y: box.minY)
        .allowsHitTesting(false)
    }
}

// MARK: - The app

/// Held up alone, not watching: lists to pick from, in our own cards. Watching is
/// `YouTubeFullscreen`, the video and nothing else.
public struct YouTubeApp: View {
    public var youtube: HudSnapshot.YouTube
    /// The live video is drawn underneath, by `YouTubeVideoLayer`; leave its place clear.
    public var live: Bool
    public var standIn: Bool
    public var hover: CGPoint?
    /// Fullscreen, or the centre's size.
    public var size: CGSize

    public init(_ youtube: HudSnapshot.YouTube, live: Bool = false, standIn: Bool = false,
                hover: CGPoint? = nil, size: CGSize = YouTubeAppLayout.size) {
        self.youtube = youtube
        self.live = live
        self.standIn = standIn
        self.hover = hover
        self.size = size
    }

    private var target: YouTubeAppLayout.Target? {
        hover.flatMap { YouTubeAppLayout.target(at: $0, youtube, in: size) }
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            browse
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .appSurface()
        // The tile's video is the live layer underneath: cut its place out of the surface.
        .mask {
            ZStack(alignment: .topLeading) {
                Rectangle()
                if live && youtube.hasVideo {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .at(YouTubeAppLayout.tileVideo(in: size))
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
        }
    }

    // ------------------------------------------------------------------ browse

    @ViewBuilder
    private var browse: some View {
        ForEach(Array(youtube.tabs.enumerated()), id: \.element) { index, tab in
            Chip(text: tab.title, symbol: tab == .search ? "magnifyingglass" : nil,
                 selected: youtube.tab == tab, hovered: target == .tab(tab))
                .at(YouTubeAppLayout.tabFrame(index, of: youtube.tabs))
        }
        if youtube.tab == .search {
            let last = YouTubeAppLayout.tabFrame(youtube.tabs.count - 1, of: youtube.tabs)
            Text(youtube.query.isEmpty ? "Search from the phone" : "\u{201C}\(youtube.query)\u{201D}")
                .font(HudTheme.mont(26, youtube.query.isEmpty ? .semibold : .black))
                .foregroundStyle(youtube.query.isEmpty ? HudTheme.inkFaint : HudTheme.ink)
                .lineLimit(1)
                .at(CGRect(x: last.maxX + 24, y: last.minY,
                           width: max((YouTubeAppLayout.wide(size) ? YouTubeAppLayout.nowPlayingTile(in: size).minX : size.width) - last.maxX - 48, 0),
                           height: last.height), alignment: .leading)
        }
        if youtube.hasVideo { nowPlaying.at(YouTubeAppLayout.nowPlayingTile(in: size)) }

        let list = youtube.list(youtube.tab)
        if list.isEmpty {
            Text(emptyText).font(HudTheme.mont(30, .semibold)).foregroundStyle(HudTheme.inkFaint)
                .at(CGRect(x: 72, y: 150, width: size.width - 144, height: size.height - 300), alignment: .center)
        } else {
            let columns = YouTubeAppLayout.columns(size)
            let visibleRows = YouTubeAppLayout.visibleRows(size)
            let first = youtube.scrollRow * columns
            ForEach(0..<(columns * visibleRows), id: \.self) { slot in
                if list.indices.contains(first + slot) {
                    let video = list[first + slot]
                    VideoCard(video: video, queued: youtube.queue.firstIndex(of: video),
                              playing: video.id == youtube.videoId,
                              hovered: target == .card(first + slot))
                        .at(YouTubeAppLayout.cardFrame(slot: slot, in: size))
                }
            }
            let rows = (list.count + columns - 1) / columns
            if rows > visibleRows, size == YouTubeAppLayout.size {
                Text("ROWS \(youtube.scrollRow + 1)\u{2013}\(min(youtube.scrollRow + 2, rows)) OF \(rows) \u{00B7} SCROLL FOR MORE")
                    .font(HudTheme.mont(18, .black)).tracking(3).foregroundStyle(HudTheme.inkFaint)
                    .at(CGRect(x: 72, y: 872, width: 1648, height: 30))
            }
        }
    }

    private var emptyText: String {
        if youtube.loading { return "Loading\u{2026}" }
        if !youtube.problem.isEmpty { return youtube.problem }
        switch youtube.tab {
        case .search: return youtube.query.isEmpty ? "Tap SEARCH on the phone and type" : "Nothing found"
        case .subscriptions: return "Nothing new from your subscriptions"
        case .home: return "Nothing here yet"
        }
    }

    private var nowPlaying: some View {
        let lit = target == .nowPlaying
        return HStack(spacing: 16) {
            PlayerFrame(live: live, standIn: standIn)
                .frame(width: 142, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(youtube.isPlaying ? "NOW PLAYING" : "PAUSED").font(HudTheme.mont(14, .black)).tracking(3)
                    .foregroundStyle(youtube.isPlaying ? HudTheme.accent : HudTheme.inkDim)
                Text(youtube.title).font(HudTheme.mont(20, .black)).foregroundStyle(HudTheme.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(2)
        .background(Color.white.opacity(lit ? 0.14 : 0.0001),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

}

// MARK: - Watching

/// The video over the whole canvas, edge to edge. The phone has the controls; the glasses only
/// say what this is, and how far along, while it is paused.
public struct YouTubeFullscreen: View {
    public var youtube: HudSnapshot.YouTube
    /// The live video is drawn underneath, by `YouTubeVideoLayer`; leave its place clear.
    public var live: Bool
    public var standIn: Bool

    public init(_ youtube: HudSnapshot.YouTube, live: Bool = false, standIn: Bool = false) {
        self.youtube = youtube
        self.live = live
        self.standIn = standIn
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            live ? Color.clear : Color.black
            PlayerFrame(live: live, standIn: standIn)
            if !youtube.notice.isEmpty {
                Text(youtube.notice).font(HudTheme.mont(30, .semibold)).foregroundStyle(HudTheme.inkDim)
                    .multilineTextAlignment(.center).padding(120)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if youtube.hasVideo && !youtube.isPlaying && !youtube.isAd {
                VStack(alignment: .leading, spacing: 12) {
                    Text(youtube.channel.uppercased()).font(HudTheme.mont(20, .black)).tracking(4)
                        .foregroundStyle(HudTheme.accent).lineLimit(1)
                    Text(youtube.title).font(HudTheme.mont(52, .black)).foregroundStyle(HudTheme.ink)
                        .lineLimit(2)
                    if !youtube.isLive {
                        HStack(spacing: 20) {
                            Text(HudSnapshot.NowPlaying.time(youtube.elapsed))
                            ProgressLine(progress: youtube.progress).frame(height: 8)
                            Text("\u{2212}" + HudSnapshot.NowPlaying.time(max(youtube.duration - youtube.elapsed, 0)))
                        }
                        .font(HudTheme.mont(24, .black)).monospacedDigit().foregroundStyle(HudTheme.inkDim)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 120).padding(.top, 200).padding(.bottom, 90)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.9)],
                                           startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(width: HudTheme.glassesSize.width, height: HudTheme.glassesSize.height)
    }
}

// MARK: - Pieces

private struct Chip: View {
    var text: String
    var symbol: String?
    var selected: Bool
    var hovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let symbol { Image(systemName: symbol).font(.system(size: 20, weight: .bold)) }
            Text(text).font(HudTheme.mont(18, .black)).tracking(2.5).lineLimit(1)
        }
        .foregroundStyle(selected ? Color.black : HudTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selected ? HudTheme.accent : Color.white.opacity(hovered ? 0.2 : 0.08), in: Capsule())
    }
}

struct Thumbnail: View {
    var video: YouTubeVideo
    var corner: CGFloat
    var badge: CGFloat = 17

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: video.thumbnail) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                // Stills have no network: a tint of its own per video.
                let hue = Double(abs(video.id.hashValue % 360)) / 360
                LinearGradient(colors: [Color(hue: hue, saturation: 0.35, brightness: 0.32),
                                        Color(hue: hue, saturation: 0.4, brightness: 0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if !video.duration.isEmpty {
                Text(video.duration).font(HudTheme.mont(badge, .black)).monospacedDigit()
                    .foregroundStyle(video.isLive ? Color.black : HudTheme.ink)
                    .padding(.horizontal, badge * 0.47).frame(height: badge * 1.65)
                    .background(video.isLive ? Color(red: 0.9, green: 0.25, blue: 0.2) : Color.black.opacity(0.8),
                                in: RoundedRectangle(cornerRadius: badge * 0.35, style: .continuous))
                    .padding(badge * 0.47)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

private struct VideoCard: View {
    var video: YouTubeVideo
    var queued: Int?
    var playing: Bool
    var hovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                Thumbnail(video: video, corner: 18)
                    .frame(width: YouTubeAppLayout.cardWidth, height: YouTubeAppLayout.thumbHeight)
                if playing || queued != nil {
                    Text(playing ? "PLAYING" : "QUEUED \(queued! + 1)").font(HudTheme.mont(14, .black)).tracking(2)
                        .foregroundStyle(.black).padding(.horizontal, 10).frame(height: 26)
                        .background(HudTheme.accent, in: Capsule()).padding(10)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hovered ? HudTheme.accent : .clear, lineWidth: 4))
            Text(video.title).font(HudTheme.mont(23, .black)).foregroundStyle(HudTheme.ink)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text([video.channel, video.meta].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                .font(HudTheme.mont(17, .semibold)).foregroundStyle(HudTheme.inkDim).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scaleEffect(hovered ? 1.02 : 1, anchor: .center)
    }
}

/// For stills: a dim frame of something playing.
struct StandInFrame: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let height = min(size.height, size.width * 9 / 16)
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.24),
                                        Color(red: 0.05, green: 0.06, blue: 0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(red: 0.85, green: 0.55, blue: 0.25).opacity(0.5))
                    .frame(width: height * 0.5).blur(radius: height * 0.12)
                    .offset(x: size.width * 0.18, y: -height * 0.08)
            }
            .frame(width: size.width, height: height)
            .position(x: size.width / 2, y: size.height / 2)
        }
    }
}

// MARK: - Watching in the centre

/// The video as large as the centre allows, with what it is and how far along under it. The live
/// video is the layer underneath; its place is cut out.
public struct YouTubeCentreWatch: View {
    public var youtube: HudSnapshot.YouTube
    public var live: Bool
    public var standIn: Bool
    public var size: CGSize

    public init(_ youtube: HudSnapshot.YouTube, live: Bool, standIn: Bool, size: CGSize) {
        self.youtube = youtube
        self.live = live
        self.standIn = standIn
        self.size = size
    }

    public var body: some View {
        let video = YouTubeAppLayout.centreVideo(in: size)
        ZStack(alignment: .topLeading) {
            if !live { PlayerFrame(live: false, standIn: standIn).at(video) }
            VStack(alignment: .leading, spacing: 10) {
                Text(youtube.isAd ? "AD" : youtube.isPlaying ? "NOW PLAYING" : "PAUSED")
                    .font(HudTheme.mont(16, .black)).tracking(3)
                    .foregroundStyle(youtube.isPlaying ? HudTheme.accent : HudTheme.inkDim)
                Text(youtube.title).font(HudTheme.mont(32, .black)).lineLimit(2).foregroundStyle(HudTheme.ink)
                Text(youtube.channel).font(HudTheme.mont(22, .semibold)).lineLimit(1).foregroundStyle(HudTheme.inkDim)
                if youtube.duration > 0 {
                    ProgressLine(progress: youtube.elapsed / max(youtube.duration, 1)).frame(height: 6).padding(.top, 6)
                }
            }
            .at(CGRect(x: video.minX, y: video.maxY + 24, width: video.width, height: size.height - video.maxY - 48),
                alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .appSurface()
        .mask {
            ZStack(alignment: .topLeading) {
                Rectangle()
                if live && youtube.hasVideo {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).at(video).blendMode(.destinationOut)
                }
            }
            .compositingGroup()
        }
    }
}
