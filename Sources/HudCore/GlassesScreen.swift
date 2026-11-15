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
    /// Which panels are on. With the browser off the middle is left clear, because the middle is
    /// where the world is.
    public var visible: Set<HudPanelKind>
    public var browserContent: AnyView?
    /// The map raster, when one has arrived.
    public var mapGround: Image?
    /// Stand-in page and procedural streets. True for stills; the device passes false, because a
    /// made-up map on someone's face is worse than an empty one.
    public var placeholders: Bool
    /// A real backdrop blur under the browser's bar. The device only; see `BrowserPanel`.
    public var liveGlass: Bool

    public init(snapshot: HudSnapshot = HudSnapshot(),
                visible: Set<HudPanelKind> = Set(HudPanelKind.allCases),
                browserContent: AnyView? = nil,
                mapGround: Image? = nil,
                placeholders: Bool = true,
                liveGlass: Bool = false) {
        self.liveGlass = liveGlass
        self.snapshot = snapshot
        self.visible = visible
        self.browserContent = browserContent
        self.mapGround = mapGround
        self.placeholders = placeholders
    }

    private var layout: GlassesLayout {
        GlassesLayout(visible: visible, tabCount: snapshot.browser.tabs.count,
                      activeTab: snapshot.browser.activeTab,
                      fullscreen: snapshot.browser.isFullscreen)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            if layout.fullscreen {
                browserPanel
            } else if visible.contains(.browser) {
                browserLayout
            } else if let solo = visible.first, visible.count == 1 {
                soloLayout(solo)
            } else {
                glanceLayout
            }

            if let cursor = snapshot.cursor {
                Cursor().offset(x: cursor.x, y: cursor.y)
            }
        }
        .frame(width: HudTheme.glassesSize.width, height: HudTheme.glassesSize.height)
        .environment(\.colorScheme, .dark)
    }

    private func minimap() -> MinimapPanel {
        MinimapPanel(snapshot.minimap, ground: mapGround, proceduralGround: placeholders)
    }

    private var browserPanel: BrowserPanel {
        BrowserPanel(snapshot.browser, content: browserContent, standIn: placeholders,
                     hovering: layout.isOverBar(snapshot.cursor),
                     hoveredTab: layout.tab(at: snapshot.cursor), liveGlass: liveGlass)
    }

    /// One panel on its own, as an app: Maps with search and directions, the forecast, the
    /// clock with the day. (The browser on its own is `browserLayout` without the column, which
    /// already takes the full width.)
    @ViewBuilder
    private func soloLayout(_ kind: HudPanelKind) -> some View {
        switch kind {
        case .map:
            MapsApp(minimap: snapshot.minimap, maps: snapshot.maps, ground: mapGround,
                    proceduralGround: placeholders, cursor: snapshot.cursor)
        case .clock:
            ClockApp(snapshot.clock).padding(HudTheme.safeInset)
        case .weather:
            WeatherApp(snapshot.weather).padding(HudTheme.safeInset)
        case .browser:
            browserLayout
        }
    }

    private var browserLayout: some View {
        HStack(alignment: .top, spacing: GlassesLayout.gap) {
            if layout.hasColumn {
                VStack(spacing: GlassesLayout.gap) {
                    if visible.contains(.clock) { ClockPanel(snapshot.clock) }
                    if visible.contains(.weather), let weather = snapshot.weather {
                        WeatherPanel(weather)
                    }
                    if visible.contains(.map) {
                        minimap().frame(maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: GlassesLayout.columnWidth)
            }

            browserPanel
        }
        .padding(HudTheme.safeInset)
    }

    /// Panels pushed to the corners. Xreal's optics are softest at the rim, so the marks sit just
    /// inside the safe inset rather than against the edge, and the centre is left alone.
    private var glanceLayout: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: GlassesLayout.gap) {
                if visible.contains(.clock) { ClockPanel(snapshot.clock).frame(width: 620) }
                Spacer(minLength: 0)
                if visible.contains(.map) { minimap().frame(width: 520, height: 340) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if visible.contains(.weather), let weather = snapshot.weather {
                WeatherPanel(weather)
                    .frame(width: 430)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .padding(HudTheme.safeInset)
    }
}
