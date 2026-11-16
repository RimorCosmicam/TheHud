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
    /// The photo library's pictures by index, as far as they have loaded: the one on show and
    /// the gallery's page.
    public var photoImages: [Int: Image]
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
                photoImages: [Int: Image] = [:],
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
        self.photoImages = photoImages
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

            // Always here, whatever else is: see `YouTubeVideoLayer`.
            if let youtubeContent {
                let place = youtubeVideo(layout)
                YouTubeVideoLayer(content: youtubeContent, box: place?.box, corner: place?.corner ?? 0)
            }

            if let solo, !solo.isBig, !layout.fullscreen, !clearView {
                if solo == .map {
                    // Maps lays its controls out on the whole canvas itself.
                    MapsApp(minimap: snapshot.minimap, maps: snapshot.maps, ground: mapGround,
                            proceduralGround: placeholders, cursor: snapshot.cursor)
                } else if solo == .youtube && snapshot.youtube.page == .player {
                    // Watching: the video is the canvas.
                    YouTubeFullscreen(snapshot.youtube, live: youtubeContent != nil, standIn: placeholders)
                } else if solo == .sky {
                    // The sky is the whole canvas, edge to edge.
                    SkyApp(snapshot.sky, overhead: snapshot.overhead, view: snapshot.skyView,
                           heading: snapshot.minimap.heading)
                } else {
                    soloApp(solo).at(GlassesLayout.safeFrame)
                }
            }
            if let (kind, frame) = layout.centreApp {
                centreApp(kind, size: frame.size, hover: hover(in: frame)).at(frame)
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

    /// Where the live video shows right now: the whole canvas while watching, the tile while
    /// browsing, its slot as a widget, or nowhere.
    private func youtubeVideo(_ layout: GlassesLayout) -> (box: CGRect, corner: CGFloat)? {
        let youtube = snapshot.youtube
        guard youtube.hasVideo, !clearView, !layout.fullscreen else { return nil }
        if solo == .youtube {
            if youtube.page == .player { return (CGRect(origin: .zero, size: HudTheme.glassesSize), 0) }
            let inset = GlassesLayout.safeFrame.origin
            return (YouTubeAppLayout.tileVideo.offsetBy(dx: inset.x, dy: inset.y), 12)
        }
        if solo == nil, let (kind, frame) = layout.centreApp, kind == .youtube {
            let box = youtube.page == .player ? YouTubeAppLayout.centreVideo(in: frame.size)
                : YouTubeAppLayout.tileVideo(in: frame.size)
            return (box.offsetBy(dx: frame.minX, dy: frame.minY), 12)
        }
        guard solo == nil, let slot = layout.widgetFrames.first(where: { $0.kind == .youtube })?.frame
        else { return nil }
        return (slot, HudTheme.cornerRadius)
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
        case .youtube: YouTubeWidget(snapshot.youtube, live: youtubeContent != nil, standIn: placeholders)
        case .calendar: CalendarWidget(snapshot.agenda)
        case .photos: PhotosWidget(snapshot.photos, image: photoImages[snapshot.photos.current])
        case .prompter: PrompterWidget(text: snapshot.note.text, prompter: snapshot.prompter)
        case .browser: preview(frame.size) { browserPanel(nil) }
        case .mac: macPanel
        }
    }

    /// The browser as a widget: the page laid out at the centre's width and shrunk into the
    /// slot, so it shows what it would there instead of a phone-width page.
    private func preview<Content: View>(_ size: CGSize, @ViewBuilder _ content: () -> Content) -> some View {
        let scale = size.width / 944
        return content()
            .frame(width: size.width / scale, height: size.height / scale)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    /// The app in the centre, laid out for the centre's size.
    @ViewBuilder
    private func centreApp(_ kind: HudPanelKind, size: CGSize, hover: CGPoint?) -> some View {
        switch kind {
        case .clock: ClockApp(snapshot.clock, timer: snapshot.timer, hover: hover, size: size)
        case .weather: WeatherApp(snapshot.weather, size: size)
        case .activity: ActivityApp(snapshot.activity, size: size)
        case .music: MusicApp(snapshot.music, artwork: artwork, hover: hover, size: size)
        case .note: NoteApp(snapshot.note, size: size)
        case .captions: CaptionsApp(snapshot.captions, size: size)
        case .map: MapWidget(snapshot.minimap, ground: mapGround, proceduralGround: placeholders)
        case .sky:
            SkyApp(snapshot.sky, overhead: snapshot.overhead, view: snapshot.skyView,
                   heading: snapshot.minimap.heading, size: size)
                .clipShape(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
        case .youtube:
            if snapshot.youtube.page == .player {
                YouTubeCentreWatch(snapshot.youtube, live: youtubeContent != nil, standIn: placeholders, size: size)
            } else {
                YouTubeApp(snapshot.youtube, live: youtubeContent != nil, standIn: placeholders,
                           hover: hover, size: size)
            }
        case .calendar: CalendarDayView(snapshot.agenda, size: size)
        case .photos: PhotoView(snapshot.photos, image: photoImages[snapshot.photos.current])
        case .prompter:
            PrompterView(text: snapshot.note.text, prompter: snapshot.prompter, fontSize: 64)
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
        case .youtube: YouTubeApp(snapshot.youtube, live: youtubeContent != nil, standIn: placeholders, hover: hover)
        case .calendar: CalendarMonthView(snapshot.agenda)
        case .photos:
            PhotosGallery(snapshot.photos, images: photoImages, size: GlassesLayout.safeFrame.size, hover: hover)
        case .prompter:
            PrompterView(text: snapshot.note.text, prompter: snapshot.prompter, fontSize: 96)
        case .map, .sky, .browser, .mac: EmptyView()
        }
    }

    /// Nil layout: a widget's preview, which nothing hovers.
    private func browserPanel(_ layout: GlassesLayout?) -> BrowserPanel {
        BrowserPanel(snapshot.browser, content: browserContent, standIn: placeholders,
                     hovering: layout?.isOverBar(snapshot.cursor) ?? false,
                     hoveredTab: layout?.tab(at: snapshot.cursor), liveGlass: liveGlass)
    }

    private var macPanel: MacPanel {
        MacPanel(snapshot.desktop, content: desktopContent, standIn: placeholders)
    }
}
