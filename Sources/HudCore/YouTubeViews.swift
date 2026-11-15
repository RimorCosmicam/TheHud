import SwiftUI

// YouTube on the glasses, drawn in the HUD's own hand. The video itself is a web view of its
// own (see `YouTubePlayer`) showing nothing but the picture; the lists, buttons and titles
// around it are ours, read from YouTube's pages with the wearer's own sign-in.

// MARK: - Layout

/// Where everything sits in the app held up alone, in the safe frame's points (1792 by 952),
/// so clicks can be worked out from the cursor.
public enum YouTubeAppLayout {
    public enum Control: CaseIterable, Sendable { case back5, playPause, forward5, next }

    public enum Target: Equatable, Sendable {
        case tab(HudSnapshot.YouTube.Tab)
        case nowPlaying
        /// A card in the browse grid, by its index in the tab's list.
        case card(Int)
        case back
        case video
        case control(Control)
        case skipAd
        /// A row in the player's side column, by its index in `sideList`.
        case side(Int)
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

    // Player.
    public static let backButton = CGRect(x: 72, y: 40, width: 220, height: 60)
    public static let video = CGRect(x: 72, y: 124, width: 1120, height: 630)
    public static let skipAd = CGRect(x: 952, y: 664, width: 220, height: 70)
    static let progress = CGRect(x: 72, y: 778, width: 1120, height: 8)
    static let titleFrame = CGRect(x: 72, y: 832, width: 720, height: 96)
    public static let sideX: CGFloat = 1232
    static let sideWidth: CGFloat = 488
    static let sideY: CGFloat = 124
    static let sideRow: CGFloat = 96
    static let sideStride: CGFloat = 112
    public static let sideRows = 7

    public static func controlFrame(_ control: Control) -> CGRect {
        let index = CGFloat(Control.allCases.firstIndex(of: control) ?? 0)
        let side: CGFloat = 84, gap: CGFloat = 14
        let x0 = video.maxX - (side * 4 + gap * 3)
        return CGRect(x: x0 + index * (side + gap), y: 836, width: side, height: side)
    }

    public static func sideFrame(_ index: Int) -> CGRect {
        CGRect(x: sideX, y: sideY + CGFloat(index) * sideStride, width: sideWidth, height: sideRow)
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
            if backButton.contains(point) { return .back }
            if youtube.canSkipAd, skipAd.contains(point) { return .skipAd }
            if video.contains(point) { return .video }
            for control in Control.allCases where controlFrame(control).contains(point) {
                return .control(control)
            }
            let count = min(youtube.sideList.count, sideRows)
            for index in 0..<count where sideFrame(index).contains(point) { return .side(index) }
            return nil
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
    public var content: AnyView?
    public var standIn: Bool

    public init(_ youtube: HudSnapshot.YouTube, content: AnyView?, standIn: Bool = false) {
        self.youtube = youtube
        self.content = content
        self.standIn = standIn
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if youtube.hasVideo {
                PlayerFrame(content: content, standIn: standIn)
                VStack(alignment: .leading, spacing: 8) {
                    Text(youtube.isAd ? "AD" : youtube.title).font(HudTheme.mont(18, .black))
                        .foregroundStyle(youtube.isAd ? HudTheme.accent : HudTheme.ink)
                        .lineLimit(1)
                    if !youtube.isLive { ProgressLine(progress: youtube.progress).frame(height: 4) }
                }
                .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 18)
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)],
                                           startPoint: .top, endPoint: .bottom))
                if !youtube.isPlaying {
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

/// The player's page, always laid out at one size and scaled to fit, so YouTube never reflows
/// its player as the video moves between a slot, a tile and the player page.
struct PlayerFrame: View {
    var content: AnyView?
    var standIn: Bool
    static let native = CGSize(width: 1280, height: 720)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = min(size.width / Self.native.width, size.height / Self.native.height)
            ZStack {
                Color.black
                if let content {
                    content
                        .frame(width: Self.native.width, height: Self.native.height)
                        .scaleEffect(scale)
                        .frame(width: Self.native.width * scale, height: Self.native.height * scale)
                } else if standIn {
                    StandInFrame()
                        .frame(width: Self.native.width * scale, height: Self.native.height * scale)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

// MARK: - The app

/// Held up alone: lists to pick from in our own cards, or the video with its controls and
/// what comes next.
public struct YouTubeApp: View {
    public var youtube: HudSnapshot.YouTube
    public var content: AnyView?
    public var standIn: Bool
    public var hover: CGPoint?

    public init(_ youtube: HudSnapshot.YouTube, content: AnyView?, standIn: Bool = false,
                hover: CGPoint? = nil) {
        self.youtube = youtube
        self.content = content
        self.standIn = standIn
        self.hover = hover
    }

    private var target: YouTubeAppLayout.Target? {
        hover.flatMap { YouTubeAppLayout.target(at: $0, youtube) }
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            switch youtube.page {
            case .browse: browse
            case .player: player
            }
        }
        .frame(width: YouTubeAppLayout.size.width, height: YouTubeAppLayout.size.height,
               alignment: .topLeading)
        .appSurface()
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
                .at(CGRect(x: last.maxX + 24, y: last.minY, width: YouTubeAppLayout.nowPlayingTile.minX - last.maxX - 48,
                           height: last.height), alignment: .leading)
        }
        if youtube.hasVideo { nowPlaying.at(YouTubeAppLayout.nowPlayingTile) }

        let list = youtube.list(youtube.tab)
        if list.isEmpty {
            Text(emptyText).font(HudTheme.mont(30, .semibold)).foregroundStyle(HudTheme.inkFaint)
                .at(CGRect(x: 72, y: 150, width: 1648, height: 600), alignment: .center)
        } else {
            let first = youtube.scrollRow * YouTubeAppLayout.columns
            ForEach(0..<(YouTubeAppLayout.columns * YouTubeAppLayout.visibleRows), id: \.self) { slot in
                if list.indices.contains(first + slot) {
                    let video = list[first + slot]
                    VideoCard(video: video, queued: youtube.queue.firstIndex(of: video),
                              playing: video.id == youtube.videoId,
                              hovered: target == .card(first + slot))
                        .at(YouTubeAppLayout.cardFrame(slot: slot))
                }
            }
            let rows = (list.count + YouTubeAppLayout.columns - 1) / YouTubeAppLayout.columns
            if rows > YouTubeAppLayout.visibleRows {
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
            PlayerFrame(content: content, standIn: standIn)
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

    // ------------------------------------------------------------------ player

    @ViewBuilder
    private var player: some View {
        Chip(text: "BROWSE", symbol: "chevron.left", selected: false, hovered: target == .back)
            .at(YouTubeAppLayout.backButton)

        ZStack(alignment: .topLeading) {
            Color.black
            if youtube.hasVideo {
                PlayerFrame(content: content, standIn: standIn)
            } else {
                Text("Pick something to watch").font(HudTheme.mont(30, .semibold))
                    .foregroundStyle(HudTheme.inkFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if youtube.isAd || youtube.isLive {
                Text(youtube.isAd ? "AD" : "LIVE").font(HudTheme.mont(18, .black)).tracking(3)
                    .foregroundStyle(.black).padding(.horizontal, 14).frame(height: 36)
                    .background(youtube.isAd ? HudTheme.accent : Color(red: 0.9, green: 0.2, blue: 0.2), in: Capsule())
                    .padding(22)
            }
            if youtube.hasVideo && !youtube.isPlaying {
                Image(systemName: "pause.fill").font(.system(size: 90, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .at(YouTubeAppLayout.video)

        if youtube.canSkipAd {
            Chip(text: "SKIP AD", symbol: "forward.end.fill", selected: true, hovered: target == .skipAd)
                .at(YouTubeAppLayout.skipAd)
        }

        if youtube.hasVideo && !youtube.isLive {
            ProgressLine(progress: youtube.progress).at(YouTubeAppLayout.progress)
            HStack {
                Text(HudSnapshot.NowPlaying.time(youtube.elapsed))
                Spacer()
                Text("\u{2212}" + HudSnapshot.NowPlaying.time(max(youtube.duration - youtube.elapsed, 0)))
            }
            .font(HudTheme.mont(20, .black)).monospacedDigit().foregroundStyle(HudTheme.inkDim)
            .at(CGRect(x: 72, y: 794, width: 1120, height: 28))
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(youtube.hasVideo ? youtube.title : "").font(HudTheme.mont(32, .black))
                .foregroundStyle(HudTheme.ink).lineLimit(2)
            Text(youtube.channel).font(HudTheme.mont(22, .semibold)).foregroundStyle(HudTheme.inkDim)
                .lineLimit(1)
        }
        .at(YouTubeAppLayout.titleFrame)

        ForEach(YouTubeAppLayout.Control.allCases, id: \.self) { control in
            ControlButton(control: control, isPlaying: youtube.isPlaying,
                          hovered: target == .control(control))
                .at(YouTubeAppLayout.controlFrame(control))
        }

        let side = youtube.sideList
        HStack(spacing: 12) {
            WidgetLabel(text: youtube.queue.isEmpty ? "UP NEXT" : "QUEUE \u{00B7} \(youtube.queue.count)",
                        accent: !youtube.queue.isEmpty)
            if !youtube.queue.isEmpty && side.count > youtube.queue.count {
                WidgetLabel(text: "THEN UP NEXT")
            }
        }
        .at(CGRect(x: YouTubeAppLayout.sideX, y: 66, width: 488, height: 30))
        ForEach(0..<min(side.count, YouTubeAppLayout.sideRows), id: \.self) { index in
            SideRow(video: side[index], queued: index < youtube.queue.count,
                    hovered: target == .side(index))
                .at(YouTubeAppLayout.sideFrame(index))
        }
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

private struct ControlButton: View {
    var control: YouTubeAppLayout.Control
    var isPlaying: Bool
    var hovered: Bool

    var body: some View {
        let symbol: String = switch control {
        case .back5: "gobackward.5"
        case .playPause: isPlaying ? "pause.fill" : "play.fill"
        case .forward5: "goforward.5"
        case .next: "forward.end.fill"
        }
        let lit = control == .playPause
        return Image(systemName: symbol)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(lit ? Color.black : HudTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(lit ? HudTheme.accent : Color.white.opacity(hovered ? 0.2 : 0.08),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(hovered && lit ? 0.85 : 1)
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

private struct SideRow: View {
    var video: YouTubeVideo
    var queued: Bool
    var hovered: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Thumbnail(video: video, corner: 12, badge: 14).frame(width: 170, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(HudTheme.mont(19, .black)).foregroundStyle(HudTheme.ink).lineLimit(2)
                Text(video.channel).font(HudTheme.mont(15, .semibold))
                    .foregroundStyle(queued ? HudTheme.accent : HudTheme.inkDim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(hovered ? 0 : 0)
        .background(Color.white.opacity(hovered ? 0.14 : 0.0001),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
