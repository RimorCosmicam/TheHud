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
    /// A little over half the display. It sits clear of the home indicator rather than under
    /// it: a swipe that starts on the bottom edge belongs to iOS, so the pad stops above it.
    public static let trackpadFraction: CGFloat = 0.56
    public static var trackpad: CGFloat { (size.height * trackpadFraction).rounded() }
    /// The home indicator's strip, which the pad stays out of.
    public static let homeIndicator: CGFloat = 34
    /// Side margin, and the gap above the keyboard when it is up.
    public static let surfaceMargin: CGFloat = 10

    /// The surface's lower corners, concentric with the display's own (55pt on the Pro phones)
    /// at the margin the pad is inset by.
    public static let surfaceBottomRadius: CGFloat = 45
    /// The upper corners: rounded to match, but tighter, because they sit mid-screen rather
    /// than against the bezel.
    public static let surfaceTopRadius: CGFloat = 30
    public static let screenCornerRadius: CGFloat = 55

    /// iOS gives the portrait keyboard about 291pt at this width, about 336pt with the
    /// predictive bar on.
    public static let keyboard: CGFloat = 291
    public static let keyboardPredictive: CGFloat = 336

    /// The settings area between the toolbar and the surface. It is the slack: the keyboard
    /// pushes everything up and this is what gets spent.
    public static func settingsHeight(keyboard: CGFloat) -> CGFloat {
        size.height - statusBar - toolBar - trackpad - bottomGap(keyboard: keyboard) - keyboard
    }

    /// Below the pad: the home indicator's strip, or a margin above the keyboard.
    public static func bottomGap(keyboard: CGFloat) -> CGFloat {
        keyboard > 0 ? surfaceMargin : homeIndicator
    }

    /// The surface's outline. With the keyboard up the surface sits on the keyboard rather than
    /// near the bezel, so the lower corners drop to the upper radius.
    public static func surfaceShape(keyboardUp: Bool,
                                    bottomRadius: CGFloat = surfaceBottomRadius)
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
    case back, forward, reload, home, favorite, address, keyboard, settings
    case newTab
    case selectTab(Int), closeTab(Int)
    case toggle(HudPanelKind)
    /// Show one panel alone on the glasses, or put the set back if it already is.
    case solo(HudPanelKind)
    /// Stream one of the Mac's windows, by its place in the list; nil for the whole screen.
    case selectWindow(Int?)
    /// With the browser and the desktop both on: list the Mac's windows instead of the tabs.
    case showWindows(Bool)
}

/// The icon row: the browser's own controls, the keyboard, and the gear.
///
/// The browser's chrome is on the glasses too, but steering a cursor onto a 52pt back arrow is
/// slow; a thumb on a button is not. So the commands you reach for constantly live here as well.
public struct HudToolBar: View {
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var keyboardUp: Bool
    /// The current site is a favourite. Nil on the start page, where there is nothing to star.
    public var isFavorite: Bool?
    public var action: (PhoneAction) -> Void

    public init(canGoBack: Bool = true, canGoForward: Bool = false, keyboardUp: Bool = false,
                isFavorite: Bool? = false,
                action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.keyboardUp = keyboardUp
        self.isFavorite = isFavorite
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", .back, enabled: canGoBack)
            button("chevron.right", .forward, enabled: canGoForward)
            button("arrow.clockwise", .reload)
            button("house", .home)
            button(isFavorite == true ? "star.fill" : "star", .favorite,
                   enabled: isFavorite != nil, lit: isFavorite == true)
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
    public var solo: HudPanelKind?
    public var glassesConnected: Bool
    public var tabs: [String]
    public var activeTab: Int
    public var desktop: HudSnapshot.Desktop
    /// Both lists are possible: whether the Mac's windows are the one showing.
    public var showsWindows: Bool
    public var action: (PhoneAction) -> Void

    public init(visible: Set<HudPanelKind> = HudPanelKind.standard,
                solo: HudPanelKind? = nil,
                glassesConnected: Bool = true,
                tabs: [String] = ["New Tab"],
                activeTab: Int = 0,
                desktop: HudSnapshot.Desktop = HudSnapshot.Desktop(),
                showsWindows: Bool = false,
                action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.visible = visible
        self.solo = solo
        self.glassesConnected = glassesConnected
        self.tabs = tabs
        self.activeTab = activeTab
        self.desktop = desktop
        self.showsWindows = showsWindows
        self.action = action
    }

    private func shown(_ kind: HudPanelKind) -> Bool {
        solo.map { $0 == kind } ?? visible.contains(kind)
    }

    /// The strip lists the Mac's windows when the desktop is on and the browser is not, or
    /// when both are and WINDOWS was picked.
    private var listsWindows: Bool {
        shown(.desktop) && (!shown(.browser) || showsWindows)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(solo == nil ? "ON THE GLASSES" : "FULLSCREEN").hudLabel()
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

            stripHeader
                .padding(.top, 10)

            if listsWindows { windowStrip } else { tabStrip }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.black)
    }

    @ViewBuilder
    private var stripHeader: some View {
        if shown(.desktop) && shown(.browser) {
            HStack(spacing: 18) {
                stripChoice("TABS", chosen: !listsWindows) { action(.showWindows(false)) }
                stripChoice("WINDOWS", chosen: listsWindows) { action(.showWindows(true)) }
            }
        } else {
            Text(listsWindows ? "WINDOWS" : "TABS").hudLabel()
        }
    }

    private func stripChoice(_ title: String, chosen: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(HudTheme.mont(16, .black)).tracking(3)
                .foregroundStyle(chosen ? HudTheme.accent : HudTheme.inkFaint)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// What the Mac can stream: the whole screen first, then each window HudCast found.
    private var windowStrip: some View {
        let active = desktop.source == nil ? -2 : (desktop.activeWindow ?? -1)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if desktop.connected {
                        windowChip("Full desktop", symbol: "display", active: active == -1) {
                            action(.selectWindow(nil))
                        }
                        .id(-1)
                        ForEach(Array(desktop.windows.enumerated()), id: \.element.id) { index, window in
                            windowChip(window.label, symbol: nil, active: active == index) {
                                action(.selectWindow(index))
                            }
                            .id(index)
                        }
                    } else {
                        Text(desktop.status)
                            .font(HudTheme.mont(10, .black)).tracking(1.5)
                            .foregroundStyle(HudTheme.inkFaint)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(HudTheme.surface)
                    }
                }
            }
            .onChange(of: active) { _, index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func windowChip(_ title: String, symbol: String?, active: Bool,
                            tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(HudTheme.mont(12, .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 170, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? HudTheme.ink : HudTheme.inkDim)
        .background(active ? Color.white.opacity(0.10) : HudTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(active ? HudTheme.accent : .clear).frame(height: 2)
        }
    }

    /// The glasses' tabs, as chips: tap to switch, the cross to close, the last chip for a new
    /// one. Steering the cursor onto a tab works too; this is the quick way.
    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, title in
                        tabChip(index, title)
                            .id(index)
                    }
                    Button { action(.newTab) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(HudTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(HudTheme.surface)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(tabs.count >= BrowserMetrics.maxTabs)
                }
            }
            .onChange(of: activeTab) { _, index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func tabChip(_ index: Int, _ title: String) -> some View {
        let active = index == activeTab
        return HStack(spacing: 0) {
            Button { action(.selectTab(index)) } label: {
                Text(title)
                    .font(HudTheme.mont(12, .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
                    .padding(.leading, 12)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if tabs.count > 1 {
                Button { action(.closeTab(index)) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 44)
            }
        }
        .foregroundStyle(active ? HudTheme.ink : HudTheme.inkDim)
        .background(active ? Color.white.opacity(0.10) : HudTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(active ? HudTheme.accent : .clear).frame(height: 2)
        }
    }

    /// Tap to put a panel on the glasses or take it off. Hold to show it fullscreen, alone on
    /// the glasses; then any tap puts things back as they were.
    private func tile(_ kind: HudPanelKind) -> some View {
        let alone = solo == kind
        let on = solo == nil ? visible.contains(kind) : alone
        return VStack(spacing: 8) {
            Image(systemName: kind.symbol)
                .font(.system(size: 22, weight: .medium))
            Text(kind.rawValue.uppercased())
                .font(HudTheme.mont(9, .black))
                .tracking(1.5)
        }
        .foregroundStyle(alone ? HudTheme.accent : on ? HudTheme.ink : HudTheme.inkFaint)
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(alone ? HudTheme.accent.opacity(0.14)
                    : on ? Color.white.opacity(0.07) : HudTheme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(on ? HudTheme.accent : .clear).frame(height: 2)
        }
        .overlay {
            if alone { Rectangle().strokeBorder(HudTheme.accent.opacity(0.6), lineWidth: 1) }
        }
        .contentShape(Rectangle())
        // One gesture, the hold tried first: a tap only counts once the finger lifts before
        // the hold completes, so a hold never also toggles the tile.
        .gesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in action(.solo(kind)) }
                .exclusively(before: TapGesture().onEnded { action(.toggle(kind)) })
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: alone)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Hold to show it alone")
        .accessibilityAction(named: "Show alone") { action(.solo(kind)) }
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
    public var solo: HudPanelKind?
    public var time: String
    public var visible: Set<HudPanelKind>
    public var desktop: HudSnapshot.Desktop
    public var showsWindows: Bool

    public init(surface: CGImage,
                railActive: Bool = false,
                cornerPressed: Bool = false,
                keyboardUp: Bool = false,
                predictiveBar: Bool = false,
                solo: HudPanelKind? = nil,
                time: String = "9:41",
                visible: Set<HudPanelKind> = [.browser, .map, .clock],
                desktop: HudSnapshot.Desktop = HudSnapshot.Desktop(),
                showsWindows: Bool = false) {
        self.visible = visible
        self.desktop = desktop
        self.showsWindows = showsWindows
        self.surface = surface
        self.railActive = railActive
        self.cornerPressed = cornerPressed
        self.keyboardUp = keyboardUp
        self.predictiveBar = predictiveBar
        self.solo = solo
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
                SettingsArea(visible: visible, solo: solo,
                             tabs: ["YouTube", "Google", "Xreal Air 2 Ultra"], activeTab: 0,
                             desktop: desktop, showsWindows: showsWindows)
                    .frame(height: settings, alignment: .top).clipped()
            } else {
                Color.black.frame(height: settings)
            }

            TrackpadSurface(surface: surface,
                            railActive: railActive,
                            cornerPressed: cornerPressed,
                            keyboardUp: keyboardUp)
                .frame(height: PhoneMetrics.trackpad)
                .padding(.horizontal, PhoneMetrics.surfaceMargin)

            Color.black.frame(height: PhoneMetrics.bottomGap(keyboard: keyboardHeight))

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
