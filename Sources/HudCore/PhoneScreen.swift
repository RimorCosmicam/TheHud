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
    /// A tap on a panel in the miniature: off for now, keeping its place, or back on. While
    /// something is fullscreen, any tap puts things back.
    case tapPanel(HudPanelKind)
    /// Show one panel alone on the glasses.
    case solo(HudPanelKind)
    /// Everything off at once, or back.
    case clearView
    case editGlasses(Bool)
    /// A drop in the editor.
    case place(HudPanelKind, HudSpot)
    /// Switch to one of the three scenes, or put one back as it was preset.
    case scene(Int), resetScene(Int)
    /// Stream one of the Mac's windows, by its place in the list; nil for the whole screen.
    case selectWindow(Int?)
    /// With the browser and the desktop both on: list the Mac's windows instead of the tabs.
    case showWindows(Bool)
    /// What the lower half of the phone is: see `PhonePad`.
    case pad(PhonePad)
    /// A thumb on one of the remote's zones, in the pad's own points.
    case remote(RemoteZone, RemoteTouchPhase, CGPoint)
    /// The fullscreen apps' own controls.
    case sky(SkyAction)
    case music(MusicLayout.Control)
    case timer(TimerAction)
    case captionsToggle, captionsSessions
    case captionsLanguage(String)
    case note(NoteAction)
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
    public var arrangement: HudArrangement
    public var solo: HudPanelKind?
    public var clearView: Bool
    /// Arranging: the miniature is big, the icons not in use are under it, and everything drags.
    public var editing: Bool
    public var glassesConnected: Bool
    public var tabs: [String]
    public var activeTab: Int
    public var desktop: HudSnapshot.Desktop
    /// Both lists are possible: whether the Mac's windows are the one showing.
    public var showsWindows: Bool
    /// The scenes' names, and which one is on.
    public var scenes: [String]
    public var currentScene: Int
    public var action: (PhoneAction) -> Void

    /// Held this long without moving, a panel goes fullscreen when let go; moved, it is dragged.
    private static let holdTime: TimeInterval = 0.4

    @State private var press: (id: Int, start: Date)?
    @State private var pressCount = 0
    /// Held long enough: a tick under the thumb, and the chip lifts.
    @State private var held: HudPanelKind?
    @State private var drag: (kind: HudPanelKind, location: CGPoint)?
    /// Where the miniature is, and where this whole area is, both on screen: a drag and its
    /// drop are measured in the same global points.
    @State private var miniFrame: CGRect = .zero
    @State private var areaOrigin: CGPoint = .zero

    public init(arrangement: HudArrangement = .standard,
                solo: HudPanelKind? = nil,
                clearView: Bool = false,
                editing: Bool = false,
                glassesConnected: Bool = true,
                tabs: [String] = ["New Tab"],
                activeTab: Int = 0,
                desktop: HudSnapshot.Desktop = HudSnapshot.Desktop(),
                showsWindows: Bool = false,
                scenes: [String] = HudScene.presets.map(\.name),
                currentScene: Int = 0,
                action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.arrangement = arrangement
        self.solo = solo
        self.clearView = clearView
        self.editing = editing
        self.glassesConnected = glassesConnected
        self.tabs = tabs
        self.activeTab = activeTab
        self.desktop = desktop
        self.showsWindows = showsWindows
        self.scenes = scenes
        self.currentScene = currentScene
        self.action = action
    }

    private func shown(_ kind: HudPanelKind) -> Bool {
        if clearView { return false }
        return solo.map { $0 == kind } ?? arrangement.isShown(kind)
    }

    /// The strip lists the Mac's windows when the Mac is on and the browser is not, or
    /// when both are and WINDOWS was picked.
    private var listsWindows: Bool {
        shown(.mac) && (!shown(.browser) || showsWindows)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            miniature
                .frame(height: editing ? 210 : 104)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { miniFrame = $0 }

            if editing {
                tray
            } else {
                stripHeader.padding(.top, 4)
                if listsWindows { windowStrip } else { tabStrip }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: editing ? .infinity : nil, alignment: .top)
        .background(.black)
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { areaOrigin = $0 }
        .overlay(alignment: .topLeading) {
            if let drag {
                MiniChip(kind: drag.kind, state: .lifted)
                    .frame(width: 92, height: 40)
                    .position(x: drag.location.x - areaOrigin.x, y: drag.location.y - areaOrigin.y)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: editing)
    }

    // MARK: header

    /// GLASSES: a tap clears the view, a hold arranges. The scenes sit beside it.
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(editing ? "ARRANGING" : clearView ? "CLEAR VIEW" : solo != nil ? "FULLSCREEN" : "GLASSES")
                    .font(HudTheme.mont(16, .black)).tracking(3)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(editing || clearView ? HudTheme.accent : HudTheme.inkDim)
                if !editing {
                    Circle()
                        .fill(glassesConnected ? HudTheme.accent : HudTheme.inkFaint)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 6)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in if !editing { action(.editGlasses(true)) } }
                    .exclusively(before: TapGesture().onEnded {
                        action(editing ? .editGlasses(false) : .clearView)
                    })
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: editing)
            .sensoryFeedback(.selection, trigger: clearView)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(glassesConnected ? "Glasses, connected" : "Glasses, not connected")
            .accessibilityHint("Tap to clear the view, hold to arrange")
            Spacer(minLength: 4)
            if editing {
                Button { action(.editGlasses(false)) } label: {
                    Text("DONE").font(HudTheme.mont(13, .black)).tracking(2)
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16).frame(height: 32)
                        .background(HudTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                sceneSwitcher.fixedSize()
            }
        }
    }

    /// The three scenes: a tap switches, a hold puts that one back as it was preset.
    private var sceneSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(scenes.indices, id: \.self) { index in
                let chosen = index == currentScene
                Text(scenes[index])
                    .font(HudTheme.mont(10, .black)).tracking(1.2)
                    .foregroundStyle(chosen ? Color.black : HudTheme.inkDim)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(chosen ? HudTheme.accent : Color.white.opacity(0.07), in: Capsule())
                    .contentShape(Capsule())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.6)
                            .onEnded { _ in action(.resetScene(index)) }
                            .exclusively(before: TapGesture().onEnded { action(.scene(index)) })
                    )
                    .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint("Tap to switch, hold to reset this scene")
            }
        }
        .sensoryFeedback(.selection, trigger: currentScene)
    }

    // MARK: miniature

    private var miniature: some View {
        GeometryReader { geometry in
            let mini = MiniLayout(size: geometry.size)
            let target = dropTarget(mini)
            ZStack(alignment: .topLeading) {
                ForEach(HudSide.allCases, id: \.self) { side in
                    ForEach(0..<HudArrangement.slotsPerSide, id: \.self) { index in
                        let frame = mini.slot(side, index)
                        slot(arrangement.slots(side)[index],
                             highlighted: target == .slot(side, index) && drag?.kind.isBig == false)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                if arrangement.bigs.isEmpty {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(editing ? 0.18 : 0.07),
                                      style: StrokeStyle(lineWidth: 1, dash: editing ? [4, 4] : []))
                        .overlay {
                            Text(editing ? "DRAG BROWSER OR MAC HERE" : "OPEN")
                                .font(HudTheme.mont(8, .black)).tracking(1.5)
                                .foregroundStyle(HudTheme.inkFaint)
                        }
                        .frame(width: mini.middle.width, height: mini.middle.height)
                        .offset(x: mini.middle.minX)
                }
                ForEach(mini.bigFrames(arrangement), id: \.kind) { kind, frame in
                    chip(kind, big: true)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
                if let drag, drag.kind.isBig, let target {
                    bigTargetMark(target, mini)
                }
            }
            .opacity(clearView && !editing ? 0.35 : 1)
        }
    }

    /// Where the dragged thing would land, if it is over the miniature.
    private func dropTarget(_ mini: MiniLayout) -> HudSpot? {
        guard let drag, miniFrame.contains(drag.location) else { return nil }
        return mini.spot(at: CGPoint(x: drag.location.x - miniFrame.minX,
                                     y: drag.location.y - miniFrame.minY))
    }

    private func bigTargetMark(_ target: HudSpot, _ mini: MiniLayout) -> some View {
        var frame = mini.middle
        if case let .slot(side, _) = target {
            frame = side == .left
                ? CGRect(x: 0, y: 0, width: mini.middle.maxX, height: mini.size.height)
                : CGRect(x: mini.middle.minX, y: 0, width: mini.size.width - mini.middle.minX,
                         height: mini.size.height)
        }
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(HudTheme.accent, lineWidth: 2)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func slot(_ kind: HudPanelKind?, highlighted: Bool) -> some View {
        if let kind {
            chip(kind, big: false)
                .overlay {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(HudTheme.accent, lineWidth: 2)
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(highlighted ? HudTheme.accent : Color.white.opacity(editing ? 0.2 : 0.06),
                              style: StrokeStyle(lineWidth: highlighted ? 2 : 1,
                                                 dash: editing && !highlighted ? [3, 3] : []))
        }
    }

    private func chipState(_ kind: HudPanelKind) -> MiniChip.State {
        if drag?.kind == kind { return .ghost }
        if solo == kind { return .solo }
        if solo != nil || arrangement.hidden.contains(kind) { return .off }
        if !kind.isBig, let side = side(of: kind), arrangement.takenSides.contains(side) {
            return .covered
        }
        return .on
    }

    private func side(of kind: HudPanelKind) -> HudSide? {
        if case let .slot(side, _) = arrangement.spot(of: kind) { return side }
        return nil
    }

    /// A widget or big panel in the miniature. Normally: tap to switch it off or on, hold for
    /// fullscreen. Arranging: drag it.
    private func chip(_ kind: HudPanelKind, big: Bool) -> some View {
        MiniChip(kind: kind, state: chipState(kind), big: big, wiggle: editing)
            .contentShape(Rectangle())
            .scaleEffect(held == kind ? 1.08 : 1)
            .animation(.easeOut(duration: 0.15), value: held == kind)
            .gesture(editing ? AnyGesture(dragGesture(kind).map { _ in () })
                             : AnyGesture(pressGesture(kind).map { _ in () }))
            .sensoryFeedback(.impact(weight: .medium), trigger: held == kind)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(kind.title)
            .accessibilityHint(editing ? "Drag to move"
                               : "Tap to switch off or on, hold to show it alone, hold and drag to move")
    }

    private func dragGesture(_ kind: HudPanelKind) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in drag = (kind, value.location) }
            .onEnded { value in
                drop(kind, at: value.location)
                drag = nil
            }
    }

    /// Outside arranging: a tap switches it off or on; held and let go, it goes fullscreen; held
    /// or pulled and dragged, it moves (the browser or the Mac over a side to take it over).
    private func pressGesture(_ kind: HudPanelKind) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if press == nil {
                    pressCount += 1
                    let id = pressCount
                    press = (id, Date())
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(Self.holdTime))
                        if press?.id == id, drag == nil { held = kind }
                    }
                }
                let moved = hypot(value.translation.width, value.translation.height)
                if drag != nil || moved > 10 { drag = (kind, value.location) }
            }
            .onEnded { value in
                let start = press?.start
                press = nil
                held = nil
                if drag != nil {
                    drag = nil
                    drop(kind, at: value.location, removing: false)
                } else if let start, Date().timeIntervalSince(start) >= Self.holdTime {
                    action(.solo(kind))
                } else {
                    action(.tapPanel(kind))
                }
            }
    }

    private func drop(_ kind: HudPanelKind, at location: CGPoint, removing: Bool = true) {
        if miniFrame.contains(location) {
            let mini = MiniLayout(size: miniFrame.size)
            let spot = mini.spot(at: CGPoint(x: location.x - miniFrame.minX,
                                             y: location.y - miniFrame.minY))
            if !kind.isBig, spot == .middle { return }
            action(.place(kind, spot))
        } else if removing, arrangement.isPlaced(kind) {
            // Dragged off the glasses: back with the icons.
            action(.place(kind, .off))
        }
    }

    // MARK: tray

    /// Everything not on the glasses, to drag on.
    private var tray: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DRAG ONTO THE GLASSES").font(HudTheme.mont(11, .black)).tracking(2)
                .foregroundStyle(HudTheme.inkFaint)
                .padding(.top, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(arrangement.unplaced) { kind in
                    MiniChip(kind: kind, state: drag?.kind == kind ? .ghost : .tray, big: true)
                        .frame(height: 72)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(kind))
                }
            }
            Text("Drop on a slot to add or replace. Drag one off to remove it. Drop Browser or Mac on a side to take that side over.")
                .font(HudTheme.mont(11, .semibold))
                .foregroundStyle(HudTheme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var stripHeader: some View {
        if shown(.mac) && shown(.browser) {
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

}

/// One panel in the miniature or the tray: its icon and name.
struct MiniChip: View {
    enum State { case on, off, covered, solo, ghost, lifted, tray }
    var kind: HudPanelKind
    var state: State
    var big = false
    var wiggle = false

    @SwiftUI.State private var tilt = false

    var body: some View {
        let layout = big ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 5))
        layout {
            Image(systemName: kind.symbol)
                .font(.system(size: big ? 18 : 12, weight: .medium))
            Text(kind.title)
                .font(HudTheme.mont(big ? 9 : 8, .black)).tracking(1)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 4)
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(state == .solo ? HudTheme.accent : Color.white.opacity(state == .on ? 0.12 : 0.05),
                              lineWidth: 1)
        }
        .overlay(alignment: .top) {
            if state == .on || state == .solo {
                Rectangle().fill(HudTheme.accent).frame(height: 2).padding(.horizontal, 6)
            }
        }
        .opacity(state == .ghost ? 0.25 : 1)
        .scaleEffect(state == .lifted ? 1.12 : 1)
        .shadow(color: .black.opacity(state == .lifted ? 0.6 : 0), radius: 10)
        .rotationEffect(.degrees(wiggle ? (tilt ? 1.2 : -1.2) : 0))
        .onAppear { if wiggle { startWiggle() } }
        .onChange(of: wiggle) { _, on in if on { startWiggle() } else { tilt = false } }
    }

    private func startWiggle() {
        withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { tilt = true }
    }

    private var foreground: Color {
        switch state {
        case .solo: return HudTheme.accent
        case .on, .lifted, .tray: return HudTheme.ink
        case .off, .covered, .ghost: return HudTheme.inkFaint
        }
    }

    private var background: Color {
        switch state {
        case .solo: return HudTheme.accent.opacity(0.14)
        case .on, .lifted: return Color(white: 0.13)
        case .tray: return Color(white: 0.1)
        case .off, .covered, .ghost: return Color(white: 0.06)
        }
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
    public var arrangement: HudArrangement
    public var clearView: Bool
    public var editing: Bool
    public var desktop: HudSnapshot.Desktop
    public var showsWindows: Bool
    public var pad: PhonePad
    /// What the fullscreen app's controls show, for `.app`.
    public var appSnapshot: HudSnapshot?

    public init(surface: CGImage,
                railActive: Bool = false,
                cornerPressed: Bool = false,
                keyboardUp: Bool = false,
                predictiveBar: Bool = false,
                solo: HudPanelKind? = nil,
                time: String = "9:41",
                arrangement: HudArrangement = .standard,
                clearView: Bool = false,
                editing: Bool = false,
                desktop: HudSnapshot.Desktop = HudSnapshot.Desktop(),
                showsWindows: Bool = false,
                pad: PhonePad = .touchpad,
                appSnapshot: HudSnapshot? = nil) {
        self.pad = pad
        self.appSnapshot = appSnapshot
        self.arrangement = arrangement
        self.clearView = clearView
        self.editing = editing
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
            // Arranging, the editor has the trackpad's room too.
            let settings = editing
                ? PhoneMetrics.size.height - PhoneMetrics.statusBar - PhoneMetrics.toolBar
                    - PhoneMetrics.homeIndicator
                : max(0, PhoneMetrics.settingsHeight(keyboard: keyboardHeight))
            if settings >= 44 {
                SettingsArea(arrangement: arrangement, solo: solo, clearView: clearView,
                             editing: editing,
                             tabs: ["YouTube", "Google", "Xreal Air 2 Ultra"], activeTab: 0,
                             desktop: desktop, showsWindows: showsWindows)
                    .frame(height: settings, alignment: .top).clipped()
            } else {
                Color.black.frame(height: settings)
            }

            if !editing {
                VStack(spacing: 0) {
                    PadHeader(current: pad, app: solo)
                    Group {
                        switch pad {
                        case .touchpad:
                            TrackpadSurface(surface: surface, railActive: railActive,
                                            cornerPressed: cornerPressed, keyboardUp: keyboardUp)
                        case .remote:
                            Image(decorative: surface, scale: PhoneMetrics.scale).resizable()
                                .overlay(RemotePad())
                        case .app:
                            AppPad(kind: solo ?? .sky, snapshot: appSnapshot ?? .blank, scrolls: false)
                        }
                    }
                    .frame(height: PhoneMetrics.trackpad - PhoneMetrics.padHeader)
                    .clipShape(PhoneMetrics.surfaceShape(keyboardUp: keyboardUp))
                }
                .frame(height: PhoneMetrics.trackpad)
                .padding(.horizontal, PhoneMetrics.surfaceMargin)
            }

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
