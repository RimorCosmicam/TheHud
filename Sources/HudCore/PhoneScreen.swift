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
    /// The icon row.
    public static let toolBar: CGFloat = 56
    /// Exactly half the display, as asked, and anchored to the bottom edge.
    public static var trackpad: CGFloat { size.height / 2 }

    /// The display's own corner radius on the Pro phones, so the surface's lower corners run
    /// parallel to the glass instead of being cut off by it.
    public static let screenCornerRadius: CGFloat = 55
    /// The surface's upper corners: rounded to match, but tighter, because they sit mid-screen
    /// rather than against the bezel.
    public static let surfaceTopRadius: CGFloat = 30

    /// iOS gives the portrait keyboard about 291pt at this width, about 336pt with the
    /// predictive bar on.
    public static let keyboard: CGFloat = 291
    public static let keyboardPredictive: CGFloat = 336

    /// The settings area between the toolbar and the surface. It is the slack: the keyboard
    /// pushes everything up and this is what gets spent.
    public static func settingsHeight(keyboard: CGFloat) -> CGFloat {
        size.height - statusBar - toolBar - trackpad - keyboard
    }

    /// The surface's outline. With the keyboard up the surface sits on the keyboard rather than
    /// on the bezel, so the lower corners drop to the upper radius.
    public static func surfaceShape(keyboardUp: Bool,
                                    bottomRadius: CGFloat = screenCornerRadius)
        -> UnevenRoundedRectangle {
        let bottom = keyboardUp ? surfaceTopRadius : bottomRadius
        return UnevenRoundedRectangle(topLeadingRadius: surfaceTopRadius,
                                      bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom,
                                      topTrailingRadius: surfaceTopRadius,
                                      style: .continuous)
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
    public var keyboardUp: Bool

    public init(surface: Image, railActive: Bool = false, cornerPressed: Bool = false,
                keyboardUp: Bool = false) {
        self.surface = surface
        self.railActive = railActive
        self.cornerPressed = cornerPressed
        self.keyboardUp = keyboardUp
    }

    public init(surface cgImage: CGImage, scale: CGFloat = PhoneMetrics.scale,
                railActive: Bool = false, cornerPressed: Bool = false, keyboardUp: Bool = false) {
        self.init(surface: Image(decorative: cgImage, scale: scale),
                  railActive: railActive, cornerPressed: cornerPressed, keyboardUp: keyboardUp)
    }

    public var body: some View {
        surface
            .resizable()
            .overlay(EdgeControlsOverlay(railActive: railActive, cornerPressed: cornerPressed))
            .clipShape(PhoneMetrics.surfaceShape(keyboardUp: keyboardUp))
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

/// What the phone's buttons can ask for. One enum so the app and the stills share the bar.
public enum PhoneAction: Sendable {
    case back, forward, reload, address, keyboard, settings
    case toggle(HudPanelKind)
}

/// The icon row: the browser's own controls, the keyboard, and the gear.
///
/// The browser's chrome is on the glasses too, but steering a cursor onto a 52pt back arrow is
/// slow; a thumb on a button is not. So the commands you reach for constantly live here as well.
public struct HudToolBar: View {
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var keyboardUp: Bool
    public var action: (PhoneAction) -> Void

    public init(canGoBack: Bool = true, canGoForward: Bool = false, keyboardUp: Bool = false,
                action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.keyboardUp = keyboardUp
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", .back, enabled: canGoBack)
            button("chevron.right", .forward, enabled: canGoForward)
            button("arrow.clockwise", .reload)
            button("magnifyingglass", .address)
            button(keyboardUp ? "keyboard.chevron.compact.down" : "keyboard", .keyboard,
                   lit: keyboardUp)

            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 22)
                .padding(.horizontal, 6)

            button("gearshape", .settings).frame(width: 52)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HudTheme.surface)
    }

    private func button(_ symbol: String, _ kind: PhoneAction, enabled: Bool = true,
                        lit: Bool = false) -> some View {
        Button { action(kind) } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                // State by brightness alone, as the Mont material asks.
                .foregroundStyle(lit ? HudTheme.accent
                                 : enabled ? HudTheme.ink : HudTheme.inkFaint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
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

/// What is on the glasses, and whether the glasses are there at all.
///
/// This is also the slack in the layout: the surface is pinned to the bottom edge at exactly half
/// the display, so when the keyboard rises it pushes everything up and this is the area that pays
/// for it. Nothing here is needed while the thumb is on the trackpad, which is what makes it the
/// right thing to lose.
public struct SettingsArea: View {
    public var visible: Set<HudPanelKind>
    public var glassesConnected: Bool
    public var action: (PhoneAction) -> Void

    public init(visible: Set<HudPanelKind> = Set(HudPanelKind.allCases),
                glassesConnected: Bool = true,
                action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.visible = visible
        self.glassesConnected = glassesConnected
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ON THE GLASSES").hudLabel()
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(glassesConnected ? HudTheme.accent : HudTheme.inkFaint)
                        .frame(width: 6, height: 6)
                    Text(glassesConnected ? "CONNECTED" : "NOT CONNECTED")
                        .font(HudTheme.mont(9, .black)).tracking(1.5)
                        .foregroundStyle(glassesConnected ? HudTheme.inkDim : HudTheme.inkFaint)
                }
            }

            HStack(spacing: 10) {
                ForEach(HudPanelKind.allCases) { kind in
                    tile(kind)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.black)
    }

    private func tile(_ kind: HudPanelKind) -> some View {
        let on = visible.contains(kind)
        return Button { action(.toggle(kind)) } label: {
            VStack(spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 22, weight: .medium))
                Text(kind.rawValue.uppercased())
                    .font(HudTheme.mont(9, .black))
                    .tracking(1.5)
            }
            .foregroundStyle(on ? HudTheme.ink : HudTheme.inkFaint)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(on ? Color.white.opacity(0.07) : HudTheme.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(on ? HudTheme.accent : .clear).frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The whole phone: status bar, the icon row, the settings area, then the surface pinned to the
/// bottom edge at exactly half the display.
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

            HudToolBar(keyboardUp: keyboardUp).frame(height: PhoneMetrics.toolBar)

            // Below a row's worth of space there is nothing legible left to show, so it
            // collapses rather than leaving a clipped sliver of a heading behind.
            let settings = max(0, PhoneMetrics.settingsHeight(keyboard: keyboardHeight))
            if settings >= 44 {
                SettingsArea(visible: [.browser, .map, .clock])
                    .frame(height: settings, alignment: .top).clipped()
            } else {
                Color.black.frame(height: settings)
            }

            TrackpadSurface(surface: surface,
                            railActive: railActive,
                            cornerPressed: cornerPressed,
                            keyboardUp: keyboardUp)
                .frame(height: PhoneMetrics.trackpad)

            if keyboardUp {
                SystemKeyboardStandIn(showsPredictiveBar: predictiveBar)
                    .frame(height: keyboardHeight)
            }
        }
        .frame(width: PhoneMetrics.size.width, height: PhoneMetrics.size.height)
        .background(.black)
        // The display's own outline, so the still shows what the bezel actually cuts.
        .clipShape(RoundedRectangle(cornerRadius: PhoneMetrics.screenCornerRadius,
                                    style: .continuous))
    }
}
