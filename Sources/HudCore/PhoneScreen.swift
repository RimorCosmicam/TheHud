import SwiftUI
import CoreGraphics

/// Device metrics for the phones that can drive the glasses at all — iPhone 15 and later with a
/// USB-C port that carries DisplayPort.
public enum PhoneMetrics {
    /// iPhone 15/16/17 Pro, in points.
    public static let size = CGSize(width: 393, height: 852)
    public static let scale: CGFloat = 3

    /// Status bar, around the Dynamic Island.
    public static let statusBar: CGFloat = 59
    /// The icon and settings row.
    public static let toolBar: CGFloat = 56
    /// Exactly half the display, as asked, and anchored to the bottom edge.
    public static var trackpad: CGFloat { size.height / 2 }

    /// iOS gives the portrait keyboard about 291pt at this width, about 336pt with the
    /// predictive bar on.
    public static let keyboard: CGFloat = 291
    public static let keyboardPredictive: CGFloat = 336

    /// The settings area between the toolbar and the surface. It is the slack: the keyboard
    /// pushes everything up and this is what gets spent.
    public static func settingsHeight(keyboard: CGFloat) -> CGFloat {
        size.height - statusBar - toolBar - trackpad - keyboard
    }
}

/// The halftone surface with MiniMate's edge controls over it.
///
/// In the app the surface is a live `MTKView`; here it is a still rendered by the same
/// `HalftoneRenderer`. Everything laid over it is identical in both, which is the point of
/// keeping the overlay a separate view from the surface.
public struct TrackpadSurface: View {
    public var surface: Image
    public var railActive: Bool
    public var cornerPressed: Bool

    public init(surface: Image, railActive: Bool = false, cornerPressed: Bool = false) {
        self.surface = surface
        self.railActive = railActive
        self.cornerPressed = cornerPressed
    }

    public init(surface cgImage: CGImage, scale: CGFloat = PhoneMetrics.scale,
                railActive: Bool = false, cornerPressed: Bool = false) {
        self.init(surface: Image(decorative: cgImage, scale: scale),
                  railActive: railActive, cornerPressed: cornerPressed)
    }

    public var body: some View {
        surface
            .resizable()
            .overlay(EdgeControlsOverlay(railActive: railActive, cornerPressed: cornerPressed))
            .clipped()
    }
}

/// Status bar. Drawn only so a still reads as a phone; the app lets iOS draw the real one.
struct StatusBar: View {
    var time: String

    var body: some View {
        HStack {
            Text(time)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 100, alignment: .center)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
            }
            .font(.system(size: 15, weight: .medium))
            .frame(width: 100, alignment: .center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
        .background(.black)
    }
}

/// What the HUD is showing, and the way into settings. Above the surface, where it is out of the
/// thumb's way: everything below this line is swept blind, so nothing tappable belongs there.
public struct HudToolBar: View {
    public struct Item: Identifiable, Sendable {
        public let id: String
        public let symbol: String
        public let active: Bool
        public init(id: String, symbol: String, active: Bool = false) {
            self.id = id
            self.symbol = symbol
            self.active = active
        }
    }

    public var items: [Item]

    public init(items: [Item] = Item.defaults) {
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: .medium))
                    // State by brightness alone, as the Mont material asks.
                    .foregroundStyle(item.active ? HudTheme.ink : HudTheme.inkFaint)
                    .frame(maxWidth: .infinity)
            }

            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 22)
                .padding(.horizontal, 6)

            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(HudTheme.inkDim)
                .frame(width: 52)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HudTheme.surface)
    }
}

public extension HudToolBar.Item {
    /// Browser, map, weather, clock, panels — the HUD's own surfaces, not other apps.
    static let defaults: [HudToolBar.Item] = [
        .init(id: "browser", symbol: "globe", active: true),
        .init(id: "map", symbol: "map"),
        .init(id: "weather", symbol: "cloud.sun"),
        .init(id: "clock", symbol: "clock"),
        .init(id: "panels", symbol: "square.grid.2x2"),
    ]
}

/// A stand-in for the system keyboard, for previews only.
///
/// The app draws no keyboard: it puts a focused, invisible text field behind the surface and lets
/// iOS raise the real `UIKeyboard` from the lower edge, so autocorrect, dictation, swipe typing,
/// every installed language and the emoji picker all come for free. This view exists purely so a
/// still shows the right proportions — it is never on the path the device takes.
public struct SystemKeyboardStandIn: View {
    /// The predictive bar costs about 45pt, which comes out of the settings area above the
    /// surface rather than out of the surface itself.
    public var showsPredictiveBar: Bool

    public init(showsPredictiveBar: Bool = false) {
        self.showsPredictiveBar = showsPredictiveBar
    }

    private static let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
    private static let backdrop = Color(red: 0.118, green: 0.118, blue: 0.129)
    private static let key = Color(red: 0.42, green: 0.42, blue: 0.44)
    private static let modifier = Color(red: 0.231, green: 0.231, blue: 0.247)

    public var body: some View {
        VStack(spacing: 0) {
            if showsPredictiveBar {
                HStack(spacing: 0) {
                    ForEach(["\u{201C}The\u{201D}", "I", "I\u{2019}m"], id: \.self) { word in
                        Text(word).font(.system(size: 17)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 45)
            }

            VStack(spacing: 11) {
                ForEach(Self.rows, id: \.self) { row in
                    HStack(spacing: 6) {
                        if row == "ZXCVBNM" { modifierKey("\u{21E7}", width: 42) }
                        ForEach(Array(row), id: \.self) { character in
                            RoundedRectangle(cornerRadius: 5).fill(Self.key)
                                .frame(height: 42)
                                .overlay(Text(String(character)).font(.system(size: 22))
                                    .foregroundStyle(.white))
                        }
                        if row == "ZXCVBNM" { modifierKey("\u{232B}", width: 42) }
                    }
                    .padding(.horizontal, row == "ASDFGHJKL" ? 20 : 3)
                }

                HStack(spacing: 6) {
                    modifierKey("123", width: 42, font: 15)
                    modifierKey("\u{1F310}", width: 42, font: 16)
                    RoundedRectangle(cornerRadius: 5).fill(Self.key).frame(height: 42)
                        .overlay(Text("space").font(.system(size: 15)).foregroundStyle(.white))
                    RoundedRectangle(cornerRadius: 5).fill(Self.modifier)
                        .frame(width: 88, height: 42)
                        .overlay(Text("return").font(.system(size: 15)).foregroundStyle(.white))
                }
                .padding(.horizontal, 3)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            Capsule().fill(.white.opacity(0.85)).frame(width: 140, height: 5).padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.backdrop)
    }

    private func modifierKey(_ text: String, width: CGFloat, font: CGFloat = 18) -> some View {
        RoundedRectangle(cornerRadius: 5).fill(Self.modifier)
            .frame(width: width, height: 42)
            .overlay(Text(text).font(.system(size: font)).foregroundStyle(.white))
    }
}

/// The icons and settings that live above the surface.
///
/// This is also the slack in the layout: the surface is pinned to the bottom edge at exactly half
/// the display, so when the keyboard rises it pushes everything up and this is the area that pays
/// for it. Nothing here is needed while the thumb is on the trackpad, which is what makes it the
/// right thing to lose.
public struct SettingsArea: View {
    public var items: [HudToolBar.Item]

    public init(items: [HudToolBar.Item] = HudToolBar.Item.defaults) {
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ON THE GLASSES").hudLabel()

            HStack(spacing: 10) {
                ForEach(items.prefix(4)) { item in
                    VStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 22, weight: .medium))
                        Text(item.id.uppercased())
                            .font(HudTheme.mont(9, .black))
                            .tracking(1.5)
                    }
                    .foregroundStyle(item.active ? HudTheme.ink : HudTheme.inkDim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .background(HudTheme.surface)
                }
            }

            Text("SURFACE").hudLabel().padding(.top, 2)

            VStack(spacing: 1) {
                settingRow("SCENE", "HALFTONE")
                settingRow("PALETTE", "MUSTARD")
                settingRow("POINTER", "1.00\u{00D7}")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.black)
    }

    private func settingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(HudTheme.mont(11, .black)).tracking(2)
                .foregroundStyle(HudTheme.inkDim)
            Spacer()
            Text(value)
                .font(HudTheme.mont(13, .black)).tracking(1.5)
                .foregroundStyle(HudTheme.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(HudTheme.surface)
    }
}

/// The whole phone: status bar, the icon and settings row, the settings area, then the surface
/// pinned to the bottom edge at exactly half the display.
///
/// The keyboard is not a region of this layout. It rises from the lower edge and pushes
/// everything above it up, the way it does in any other app, so the surface stays whole and the
/// settings area is what shrinks.
public struct PhoneScreen: View {
    public var surface: CGImage
    public var railActive: Bool
    public var cornerPressed: Bool
    public var keyboardUp: Bool
    public var predictiveBar: Bool
    public var time: String

    public init(surface: CGImage,
                railActive: Bool = false,
                cornerPressed: Bool = false,
                keyboardUp: Bool = false,
                predictiveBar: Bool = false,
                time: String = "9:41") {
        self.surface = surface
        self.railActive = railActive
        self.cornerPressed = cornerPressed
        self.keyboardUp = keyboardUp
        self.predictiveBar = predictiveBar
        self.time = time
    }

    private var keyboardHeight: CGFloat {
        guard keyboardUp else { return 0 }
        return predictiveBar ? PhoneMetrics.keyboardPredictive : PhoneMetrics.keyboard
    }

    public var body: some View {
        VStack(spacing: 0) {
            StatusBar(time: time).frame(height: PhoneMetrics.statusBar)

            HudToolBar().frame(height: PhoneMetrics.toolBar)

            // Below a row's worth of space there is nothing legible left to show, so it
            // collapses rather than leaving a clipped sliver of a heading behind.
            let settings = max(0, PhoneMetrics.settingsHeight(keyboard: keyboardHeight))
            if settings >= 44 {
                SettingsArea().frame(height: settings, alignment: .top).clipped()
            } else {
                Color.black.frame(height: settings)
            }

            TrackpadSurface(surface: surface,
                            railActive: railActive,
                            cornerPressed: cornerPressed)
                .frame(height: PhoneMetrics.trackpad)

            if keyboardUp {
                SystemKeyboardStandIn(showsPredictiveBar: predictiveBar)
                    .frame(height: keyboardHeight)
            }
        }
        .frame(width: PhoneMetrics.size.width, height: PhoneMetrics.size.height)
        .background(.black)
    }
}
