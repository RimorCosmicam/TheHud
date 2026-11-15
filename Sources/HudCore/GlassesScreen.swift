import SwiftUI
import CoreGraphics

/// The 1920x1080 canvas the glasses are given over DisplayPort.
///
/// Black is the background, and not for taste: the Air is a birdbath combiner, so a black pixel
/// is one the world shows through. A field drawn edge to edge would veil everything the wearer is
/// looking at and burn battery doing it. The halftone belongs on the phone, where it is a surface
/// a thumb rests on; here the rule is sparse bright marks on black.
public struct GlassesScreen: View {
    public var snapshot: HudSnapshot
    public var arrangement: HudArrangement
    /// One panel held up alone.
    public var solo: HudPanelKind?
    /// Everything off: the glasses show the world.
    public var clearView: Bool
    public var browserContent: AnyView?
    /// The Mac's picture. Nil draws a stand-in desktop when `placeholders` is on.
    public var desktopContent: AnyView?
    /// The YouTube player's page. Nil draws a stand-in frame when `placeholders` is on.
    public var youtubeContent: AnyView?
    /// The map raster, when one has arrived.
    public var mapGround: Image?
    /// The Music app's artwork for what is playing.
    public var artwork: Image?
    /// Stand-in page and procedural streets. True for stills; the device passes false, because a
    /// made-up map on someone's face is worse than an empty one.
    public var placeholders: Bool
    /// A real backdrop blur under the browser's bar. The device only; see `BrowserPanel`.
    public var liveGlass: Bool

    public init(snapshot: HudSnapshot = HudSnapshot(),
                arrangement: HudArrangement = .standard,
                solo: HudPanelKind? = nil,
                clearView: Bool = false,
                browserContent: AnyView? = nil,
                desktopContent: AnyView? = nil,
                youtubeContent: AnyView? = nil,
                mapGround: Image? = nil,
                artwork: Image? = nil,
                placeholders: Bool = true,
                liveGlass: Bool = false) {
        self.snapshot = snapshot
        self.arrangement = arrangement
        self.solo = solo
        self.clearView = clearView
        self.browserContent = browserContent
        self.desktopContent = desktopContent
        self.youtubeContent = youtubeContent
        self.mapGround = mapGround
        self.artwork = artwork
        self.placeholders = placeholders
        self.liveGlass = liveGlass
    }

    /// What is on, as a set: widgets fill the left slots then the right. For stills.
    public init(snapshot: HudSnapshot = HudSnapshot(), visible: Set<HudPanelKind>,
                solo: HudPanelKind? = nil, mapGround: Image? = nil, placeholders: Bool = true) {
        self.init(snapshot: snapshot, arrangement: HudArrangement(visible: visible), solo: solo,
                  mapGround: mapGround, placeholders: placeholders)
    }

    private var layout: GlassesLayout {
        GlassesLayout(arrangement: arrangement, solo: solo, clearView: clearView,
                      tabCount: snapshot.browser.tabs.count,
                      activeTab: snapshot.browser.activeTab,
                      fullscreen: snapshot.browser.isFullscreen,
                      desktopAspect: snapshot.desktop.aspect)
    }

    public var body: some View {
        let layout = layout
        ZStack(alignment: .topLeading) {
            Color.black

            if let solo, !solo.isBig, !layout.fullscreen, !clearView {
                if solo == .map {
                    // Maps lays its controls out on the whole canvas itself.
                    MapsApp(minimap: snapshot.minimap, maps: snapshot.maps, ground: mapGround,
                            proceduralGround: placeholders, cursor: snapshot.cursor)
                } else if solo == .sky {
                    // The sky is the whole canvas, edge to edge.
                    SkyApp(snapshot.sky, overhead: snapshot.overhead, view: snapshot.skyView,
                           heading: snapshot.minimap.heading)
                } else {
                    soloApp(solo).at(GlassesLayout.safeFrame)
                }
            }
            ForEach(layout.widgetFrames, id: \.kind) { kind, frame in
                widget(kind, frame: frame).at(frame)
            }
            ForEach(layout.bigFrames, id: \.kind) { kind, frame in
                Group {
                    if kind == .browser { browserPanel(layout) } else { macPanel }
                }
                .at(frame)
            }

            if timerToast, !clearView {
                toast.at(CGRect(x: 0, y: 24, width: HudTheme.glassesSize.width, height: 90),
                         alignment: .top)
            }

            if let cursor = snapshot.cursor, showsCursor(layout, cursor) {
                Cursor().offset(x: cursor.x, y: cursor.y)
            }
        }
        .frame(width: HudTheme.glassesSize.width, height: HudTheme.glassesSize.height)
        .environment(\.colorScheme, .dark)
    }

    /// Over the Mac's picture the Mac draws its own pointer, which is the one that matters
    /// there; two would only disagree by the stream's lag.
    private func showsCursor(_ layout: GlassesLayout, _ cursor: CGPoint) -> Bool {
        if clearView { return false }
        if snapshot.desktop.hasPicture, let picture = layout.desktopPicture,
           picture.contains(cursor) { return false }
        return true
    }

    /// The timer ran out while the clock app is not up: say so where it will be seen.
    private var timerToast: Bool {
        snapshot.timer.state == .done && solo != .clock
    }

    private var toast: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer").font(.system(size: 30, weight: .bold))
            Text("TIME'S UP").font(HudTheme.mont(30, .black)).tracking(4)
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 34)
        .frame(height: 76)
        .background(HudTheme.accent, in: Capsule())
    }

    /// The cursor in a frame's own points, for hover marks.
    private func hover(in frame: CGRect) -> CGPoint? {
        guard let cursor = snapshot.cursor, frame.contains(cursor) else { return nil }
        return CGPoint(x: cursor.x - frame.minX, y: cursor.y - frame.minY)
    }

    @ViewBuilder
    private func widget(_ kind: HudPanelKind, frame: CGRect) -> some View {
        switch kind {
        case .clock: ClockWidget(snapshot.clock, timer: snapshot.timer)
        case .weather: WeatherWidget(snapshot.weather)
        case .map: MapWidget(snapshot.minimap, ground: mapGround, proceduralGround: placeholders)
        case .activity: ActivityWidget(snapshot.activity)
        case .sky: SkyWidget(snapshot.sky)
        case .music: MusicWidget(snapshot.music, artwork: artwork, hover: hover(in: frame))
        case .note: NoteWidget(snapshot.note)
        case .captions: CaptionsWidget(snapshot.captions)
        case .youtube: YouTubeWidget(snapshot.youtube, content: youtubeContent, standIn: placeholders)
        case .browser, .mac: EmptyView()
        }
    }

    /// One widget on its own, as an app.
    @ViewBuilder
    private func soloApp(_ kind: HudPanelKind) -> some View {
        let hover = hover(in: GlassesLayout.safeFrame)
        switch kind {
        case .clock: ClockApp(snapshot.clock, timer: snapshot.timer, hover: hover)
        case .weather: WeatherApp(snapshot.weather)
        case .activity: ActivityApp(snapshot.activity)
        case .music: MusicApp(snapshot.music, artwork: artwork, hover: hover)
        case .note: NoteApp(snapshot.note)
        case .captions: CaptionsApp(snapshot.captions)
        case .youtube: YouTubeApp(snapshot.youtube, content: youtubeContent, standIn: placeholders, hover: hover)
        case .map, .sky, .browser, .mac: EmptyView()
        }
    }

    private func browserPanel(_ layout: GlassesLayout) -> BrowserPanel {
        BrowserPanel(snapshot.browser, content: browserContent, standIn: placeholders,
                     hovering: layout.isOverBar(snapshot.cursor),
                     hoveredTab: layout.tab(at: snapshot.cursor), liveGlass: liveGlass)
    }

    private var macPanel: MacPanel {
        MacPanel(snapshot.desktop, content: desktopContent, standIn: placeholders)
    }
}
