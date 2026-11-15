import SwiftUI
import CoreGraphics

/// The 1920x1080 canvas the glasses are given over DisplayPort.
///
/// Black is the background, and not for taste: the Air is a birdbath combiner, so a black pixel
/// is one the world shows through. A field drawn edge to edge would veil everything the wearer is
/// looking at and burn battery doing it. The halftone belongs on the phone, where it is a surface
/// a thumb rests on; here the rule is sparse bright marks on black.
public struct GlassesScreen: View {
    public enum Mode: Sendable {
        /// The browser takes the canvas, with the panels in a column beside it.
        case browser
        /// No browser. The middle is left clear, because the middle is where the world is.
        case glance
    }

    public var snapshot: HudSnapshot
    public var mode: Mode
    public var browserContent: Image?

    public init(snapshot: HudSnapshot = HudSnapshot(),
                mode: Mode = .browser,
                browserContent: Image? = nil) {
        self.snapshot = snapshot
        self.mode = mode
        self.browserContent = browserContent
    }

    private static let columnWidth: CGFloat = 470
    private static let gap: CGFloat = 24

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            switch mode {
            case .browser: browserLayout
            case .glance: glanceLayout
            }

            if let cursor = snapshot.cursor {
                Cursor().offset(x: cursor.x, y: cursor.y)
            }
        }
        .frame(width: HudTheme.glassesSize.width, height: HudTheme.glassesSize.height)
        .environment(\.colorScheme, .dark)
    }

    private var browserLayout: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            VStack(spacing: Self.gap) {
                ClockPanel(snapshot.clock)
                WeatherPanel(snapshot.weather)
                MinimapPanel(snapshot.minimap).frame(maxHeight: .infinity)
            }
            .frame(width: Self.columnWidth)

            BrowserPanel(snapshot.browser, content: browserContent)
        }
        .padding(HudTheme.safeInset)
    }

    /// Panels pushed to the corners. Xreal's optics are softest at the rim, so the marks sit just
    /// inside the safe inset rather than against the edge, and the centre is left alone.
    private var glanceLayout: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Self.gap) {
                ClockPanel(snapshot.clock).frame(width: 620)
                Spacer(minLength: 0)
                MinimapPanel(snapshot.minimap).frame(width: 520, height: 340)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WeatherPanel(snapshot.weather)
                .frame(width: 430)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(HudTheme.safeInset)
    }
}
