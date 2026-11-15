import SwiftUI

// What the phone's lower half is. The trackpad is made for the HUD and the browser; pointing
// the phone like a remote is quicker and rougher; and the fullscreen apps where a cursor is
// clumsy get controls of their own.

/// The lower half of the phone.
public enum PhonePad: Hashable, Sendable {
    case touchpad, remote
    /// The fullscreen app's own controls.
    case app
}

extension HudPanelKind {
    /// Apps that are better worked with a thumb than a cursor when they fill the glasses.
    public var hasPhoneControls: Bool {
        switch self {
        case .sky, .music, .clock, .captions, .note, .youtube: return true
        default: return false
        }
    }

    var padTitle: String {
        switch self {
        case .clock: return "TIMER"
        default: return title
        }
    }
}

public enum RemoteZone: Int, CaseIterable, Sendable {
    case click, scroll, rightClick, centre
}

public enum RemoteTouchPhase: Sendable {
    case began, moved, ended
}

public enum SkyAction: Sendable {
    /// Degrees to look round and up.
    case look(pan: Double, tilt: Double)
    /// Multiplies how much sky is shown: under 1 is closer.
    case zoom(Double)
    case recentre
    case toggle(SkyLayer)
    case select(String?)
}

public enum TimerAction: Sendable {
    case toggle, reset
    /// Minutes to count down from; 0 is the stopwatch.
    case set(minutes: Int)
    case add(minutes: Int)
}

public enum YouTubeAction: Sendable, Equatable {
    case togglePlay, next, skipAd
    /// Seconds to jump, back (negative) or on.
    case seek(Double)
    /// Raise the keyboard to search YouTube; the glasses keep playing.
    case search
    case play(YouTubeVideo)
    /// Play something from the queue, taking it out.
    case playQueued(Int)
    case enqueue(YouTubeVideo)
    case dequeue(Int)
    /// On the glasses: the lists, or the video over everything.
    case page(HudSnapshot.YouTube.Page)
}

public enum NoteAction: Sendable {
    case write, clear
    /// Teleprompter: lines down (positive) or up.
    case scroll(CGFloat)
}

extension PhoneMetrics {
    /// The row above the surface that names it and switches it.
    public static let padHeader: CGFloat = 34
}

// MARK: - Header

/// TOUCHPAD · REMOTE, and the app's name first when it has controls. A tap on a name switches to
/// it; a tap on the one already on goes to the next.
public struct PadHeader: View {
    public var current: PhonePad
    public var app: HudPanelKind?
    public var action: (PhoneAction) -> Void

    public init(current: PhonePad, app: HudPanelKind?, action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.current = current
        self.app = app
        self.action = action
    }

    private var choices: [PhonePad] {
        (app?.hasPhoneControls == true ? [.app] : []) + [.touchpad, .remote]
    }

    private func title(_ pad: PhonePad) -> String {
        switch pad {
        case .touchpad: return "TOUCHPAD"
        case .remote: return "REMOTE"
        case .app: return app?.padTitle ?? ""
        }
    }

    private var hint: String {
        switch current {
        case .touchpad: return ""
        case .remote: return "POINT THE PHONE"
        case .app:
            switch app {
            case .sky: return "DRAG TO LOOK \u{00B7} PINCH TO ZOOM"
            default: return ""
            }
        }
    }

    public var body: some View {
        HStack(spacing: 16) {
            ForEach(choices, id: \.self) { pad in
                let on = pad == current
                Button {
                    if on, let index = choices.firstIndex(of: pad) {
                        action(.pad(choices[(index + 1) % choices.count]))
                    } else {
                        action(.pad(pad))
                    }
                } label: {
                    HStack(spacing: 6) {
                        if pad == .app, let app {
                            Image(systemName: app.symbol).font(.system(size: 11, weight: .bold))
                        }
                        Text(title(pad)).font(HudTheme.mont(12, .black)).tracking(2.2)
                            .lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(on ? HudTheme.ink : HudTheme.inkFaint)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(on ? HudTheme.accent : .clear).frame(height: 2.5).offset(y: 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Text(choices.count > 2 ? "" : hint).font(HudTheme.mont(9, .black)).tracking(1.6)
                .foregroundStyle(HudTheme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 18)
        .frame(height: PhoneMetrics.padHeader)
    }
}

// MARK: - Remote

public enum RemotePadLayout {
    public static let gap: CGFloat = 8
    public static let scrollWidth: CGFloat = 74
    public static let centreHeight: CGFloat = 62

    public static func frame(_ zone: RemoteZone, in size: CGSize) -> CGRect {
        let top = size.height - centreHeight - gap
        let side = (size.width - scrollWidth - gap * 2) / 2
        switch zone {
        case .click: return CGRect(x: 0, y: 0, width: side, height: top)
        case .scroll: return CGRect(x: side + gap, y: 0, width: scrollWidth, height: top)
        case .rightClick: return CGRect(x: side + gap * 2 + scrollWidth, y: 0, width: side, height: top)
        case .centre: return CGRect(x: 0, y: size.height - centreHeight, width: size.width, height: centreHeight)
        }
    }
}

/// The phone as a remote: pointing moves the cursor, and the surface is cut into a few big
/// zones that need no aim. Laid over the halftone, which shows through each zone and ripples
/// under the thumb.
public struct RemotePad: View {
    public var pressed: Set<RemoteZone>
    public var onTouch: (RemoteZone, RemoteTouchPhase, CGPoint) -> Void
    @State private var down: Set<RemoteZone> = []

    public init(pressed: Set<RemoteZone> = [],
                onTouch: @escaping (RemoteZone, RemoteTouchPhase, CGPoint) -> Void = { _, _, _ in }) {
        self.pressed = pressed
        self.onTouch = onTouch
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                // Black between the zones, so each reads as a pad of its own.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    for zone in RemoteZone.allCases {
                        path.addRoundedRect(in: RemotePadLayout.frame(zone, in: size),
                                            cornerSize: CGSize(width: 22, height: 22), style: .continuous)
                    }
                }
                .fill(Color.black, style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                ForEach(RemoteZone.allCases, id: \.self) { zone in
                    let frame = RemotePadLayout.frame(zone, in: size)
                    zoneView(zone, lit: pressed.contains(zone) || down.contains(zone))
                        .frame(width: frame.width, height: frame.height)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("remotePad"))
                            .onChanged { value in
                                if down.insert(zone).inserted {
                                    onTouch(zone, .began, value.location)
                                } else {
                                    onTouch(zone, .moved, value.location)
                                }
                            }
                            .onEnded { value in
                                down.remove(zone)
                                onTouch(zone, .ended, value.location)
                            })
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .coordinateSpace(name: "remotePad")
        }
    }

    @ViewBuilder
    private func zoneView(_ zone: RemoteZone, lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(lit ? 0.12 : 0))
            shape.strokeBorder(lit ? HudTheme.accent : Color.white.opacity(0.14), lineWidth: lit ? 2 : 1)
            switch zone {
            case .click:
                label("cursorarrow.click", "CLICK", "HOLD TO DRAG")
            case .rightClick:
                label("contextualmenu.and.cursorarrow", "RIGHT CLICK", nil)
            case .scroll:
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .bold))
                    Spacer()
                    VStack(spacing: 9) {
                        ForEach(0..<9, id: \.self) { _ in
                            Capsule().fill(Color.white.opacity(0.55)).frame(width: 26, height: 2)
                        }
                    }
                    .padding(.vertical, 12).padding(.horizontal, 12)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(HudTheme.inkDim)
                .padding(.vertical, 18)
            case .centre:
                HStack(spacing: 8) {
                    Image(systemName: "scope").font(.system(size: 15, weight: .bold))
                    Text("CENTRE").font(HudTheme.mont(12, .black)).tracking(2.5)
                }
                .foregroundStyle(HudTheme.ink)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.black.opacity(0.75), in: Capsule())
            }
        }
    }

    private func label(_ symbol: String, _ title: String, _ detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .semibold))
            Text(title).font(HudTheme.mont(13, .black)).tracking(2.5)
            if let detail {
                Text(detail).font(HudTheme.mont(9, .black)).tracking(1.6).foregroundStyle(HudTheme.inkDim)
            }
        }
        .foregroundStyle(HudTheme.ink)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Shared pieces

private struct PadCard<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(HudTheme.edge, lineWidth: 1))
    }
}

private struct PadButton: View {
    var symbol: String
    var title: String?
    var lit = false
    var big = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: big ? 30 : 20, weight: .bold))
                if let title {
                    Text(title).font(HudTheme.mont(10, .black)).tracking(1.8)
                }
            }
            .foregroundStyle(lit ? Color.black : HudTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(lit ? HudTheme.accent : Color(white: 0.14),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedStyle())
    }
}

private struct PressedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Sky

/// The sky's controls: a pad to look round with, the layers, and what is up right now. A tap on
/// one of those points it out on the glasses.
public struct SkyControls: View {
    public var sky: HudSnapshot.Sky
    public var overhead: HudSnapshot.Overhead
    public var view: SkyView
    public var heading: Double
    public var action: (PhoneAction) -> Void
    /// Off for stills, which cannot draw a scroll view's contents.
    public var scrolls = true
    @State private var lastDrag: CGSize = .zero
    @State private var lastScale: CGFloat = 1

    public init(sky: HudSnapshot.Sky, overhead: HudSnapshot.Overhead, view: SkyView, heading: Double,
                scrolls: Bool = true, action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.scrolls = scrolls
        self.sky = sky
        self.overhead = overhead
        self.view = view
        self.heading = heading
        self.action = action
    }

    private var targets: [SkyTarget] {
        SkyTarget.all(sky: sky, overhead: overhead, layers: view.layers).filter(\.isUp)
    }

    public var body: some View {
        VStack(spacing: 8) {
            lookPad.frame(height: 150).layoutPriority(1)
            layers.layoutPriority(1)
            list.frame(minHeight: 0, maxHeight: .infinity)
        }
    }

    private var facing: Double {
        ((heading + view.pan).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    private var lookPad: some View {
        PadCard {
            ZStack {
                // A strip of compass that slides under the thumb.
                Canvas { context, size in
                    let perDegree = size.width / CGFloat(view.fov)
                    let horizonY = size.height * (0.72 + CGFloat(view.tilt) / 70 * 0.2)
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: horizonY))
                    line.addLine(to: CGPoint(x: size.width, y: horizonY))
                    context.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 1)
                    let start = Int((facing - view.fov / 2).rounded(.down))
                    for azimuth in start...Int((facing + view.fov / 2).rounded(.up)) where azimuth % 5 == 0 {
                        let x = size.width / 2 + CGFloat(Double(azimuth) - facing) * perDegree
                        let a = ((azimuth % 360) + 360) % 360
                        let major = a % 45 == 0
                        var tick = Path()
                        tick.move(to: CGPoint(x: x, y: horizonY))
                        tick.addLine(to: CGPoint(x: x, y: horizonY + (major ? 12 : a % 15 == 0 ? 7 : 3)))
                        context.stroke(tick, with: .color(.white.opacity(major ? 0.7 : 0.3)), lineWidth: major ? 1.6 : 1)
                        if major {
                            let name = SkyModel.compass(Double(a))
                            context.draw(Text(name).font(HudTheme.mont(13, .black))
                                .foregroundColor(name == "N" ? HudTheme.accent : .white.opacity(0.8)),
                                         at: CGPoint(x: x, y: horizonY + 24))
                        }
                    }
                    // What is up, as dots where they would be.
                    for target in targets.prefix(40) {
                        var d = (target.az - facing).truncatingRemainder(dividingBy: 360)
                        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                        guard abs(d) < view.fov / 2 else { continue }
                        let x = size.width / 2 + CGFloat(d) * perDegree
                        let y = horizonY - CGFloat(target.alt - view.tilt + 4) / 90 * horizonY * 1.1
                        guard y > 6 else { continue }
                        let r: CGFloat = target.id == view.selected ? 5 : 2.2
                        let colour: Color = target.kind == .plane || target.kind == .station
                            ? Color(red: 0.55, green: 0.85, blue: 1) : target.kind == .sign ? HudTheme.accent : .white
                        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                     with: .color(colour.opacity(target.id == view.selected ? 1 : 0.7)))
                    }
                    // The middle of the glasses.
                    var cross = Path()
                    cross.move(to: CGPoint(x: size.width / 2, y: 10))
                    cross.addLine(to: CGPoint(x: size.width / 2, y: size.height - 10))
                    context.stroke(cross, with: .color(HudTheme.accent.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                }
                VStack {
                    HStack {
                        Text("\(SkyModel.compass(facing)) \(Int(facing.rounded()) % 360)\u{00B0}")
                            .font(HudTheme.mont(15, .black)).foregroundStyle(HudTheme.ink)
                        Spacer()
                        Text("\(Int(view.fov.rounded()))\u{00B0}").font(HudTheme.mont(12, .black))
                            .foregroundStyle(HudTheme.inkDim)
                        if view.isAdjusted {
                            Button { action(.sky(.recentre)) } label: {
                                Text("RESET").font(HudTheme.mont(10, .black)).tracking(1.6)
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(HudTheme.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let dx = value.translation.width - lastDrag.width
                    let dy = value.translation.height - lastDrag.height
                    lastDrag = value.translation
                    // The sky follows the thumb, as a map does.
                    let perPoint = view.fov / 360
                    action(.sky(.look(pan: -Double(dx) * perPoint, tilt: Double(dy) * perPoint)))
                }
                .onEnded { _ in lastDrag = .zero })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in
                    let step = value.magnification / lastScale
                    lastScale = value.magnification
                    action(.sky(.zoom(1 / Double(step))))
                }
                .onEnded { _ in lastScale = 1 })
            .onTapGesture(count: 2) { action(.sky(.recentre)) }
        }
    }

    private var layers: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(SkyLayer.allCases, id: \.self) { layer in
                    let on = view.layers.contains(layer)
                    Button { action(.sky(.toggle(layer))) } label: {
                        Text(layer.title).font(HudTheme.mont(10, .black)).tracking(1.2)
                            .foregroundStyle(on ? Color.black : HudTheme.inkDim)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(on ? HudTheme.accent : Color(white: 0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
        }
    }

    private var list: some View {
        PadCard {
            Group {
                if scrolls {
                    ScrollView { rows }
                } else {
                    rows.frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var rows: some View {
                LazyVStack(spacing: 0) {
                    ForEach(targets) { target in
                        let on = target.id == view.selected
                        Button { action(.sky(.select(on ? nil : target.id))) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: symbol(target)).font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(on ? HudTheme.accent : HudTheme.inkDim)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.name).font(HudTheme.mont(14, .black))
                                        .foregroundStyle(on ? HudTheme.accent : HudTheme.ink).lineLimit(1)
                                    Text(target.detail.isEmpty ? target.kind.rawValue : target.detail)
                                        .font(HudTheme.mont(10, .semibold)).foregroundStyle(HudTheme.inkDim)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text("\(Int(target.alt.rounded()))\u{00B0} \(SkyModel.compass(target.az))")
                                    .font(HudTheme.mont(12, .black)).foregroundStyle(HudTheme.inkDim)
                            }
                            .padding(.horizontal, 14).frame(height: 46)
                            .background(on ? HudTheme.accent.opacity(0.12) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
    }

    private func symbol(_ target: SkyTarget) -> String {
        switch target.kind {
        case .plane: return "airplane"
        case .station: return "antenna.radiowaves.left.and.right"
        case .sun: return "sun.max.fill"
        case .moon: return sky.moonSymbol
        case .planet: return "circle.circle"
        case .star: return "sparkle"
        case .sign: return "seal"
        }
    }
}

// MARK: - Music

public struct MusicControls: View {
    public var music: HudSnapshot.NowPlaying?
    public var action: (PhoneAction) -> Void

    public init(music: HudSnapshot.NowPlaying?, action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.music = music
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            PadCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(music?.isPlaying == true ? "NOW PLAYING" : "MUSIC").font(HudTheme.mont(10, .black))
                        .tracking(2).foregroundStyle(music?.isPlaying == true ? HudTheme.accent : HudTheme.inkDim)
                    Text(music?.title ?? "Nothing playing").font(HudTheme.mont(22, .black))
                        .foregroundStyle(HudTheme.ink).lineLimit(2)
                    Text(music?.artist ?? "Play something in the Music app").font(HudTheme.mont(14, .semibold))
                        .foregroundStyle(HudTheme.inkDim).lineLimit(1)
                    if let music {
                        ProgressLine(progress: music.progress).frame(height: 5).padding(.top, 10)
                        HStack {
                            Text(HudSnapshot.NowPlaying.time(music.elapsed))
                            Spacer()
                            Text("\u{2212}" + HudSnapshot.NowPlaying.time(max(music.duration - music.elapsed, 0)))
                        }
                        .font(HudTheme.mont(11, .black)).monospacedDigit().foregroundStyle(HudTheme.inkDim)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                PadButton(symbol: "backward.fill", title: nil) { action(.music(.previous)) }.frame(width: 92)
                PadButton(symbol: music?.isPlaying == true ? "pause.fill" : "play.fill", title: nil,
                          lit: true, big: true) { action(.music(.playPause)) }
                PadButton(symbol: "forward.fill", title: nil) { action(.music(.next)) }.frame(width: 92)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Timer

public struct TimerControls: View {
    public var timer: HudSnapshot.TimerReading
    public var action: (PhoneAction) -> Void

    public init(timer: HudSnapshot.TimerReading, action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.timer = timer
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            PadCard {
                VStack(spacing: 4) {
                    Text(timer.isStopwatch ? "STOPWATCH" : stateTitle).font(HudTheme.mont(10, .black))
                        .tracking(2).foregroundStyle(timer.state == .running ? HudTheme.accent : HudTheme.inkDim)
                    Text(timer.text).font(HudTheme.mont(64, .black)).monospacedDigit()
                        .foregroundStyle(HudTheme.ink).lineLimit(1).minimumScaleFactor(0.5)
                    if let progress = timer.progress {
                        ProgressLine(progress: progress).frame(height: 5).padding(.horizontal, 30).padding(.top, 4)
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach([1, 3, 5, 10, 15, 25, 45, 0], id: \.self) { minutes in
                    chip(minutes == 0 ? "STOPWATCH" : "\(minutes) MIN") {
                        action(.timer(.set(minutes: minutes)))
                    }
                }
            }
            HStack(spacing: 10) {
                PadButton(symbol: "arrow.counterclockwise", title: "RESET") { action(.timer(.reset)) }.frame(width: 92)
                PadButton(symbol: timer.state == .running ? "pause.fill" : "play.fill",
                          title: timer.state == .running ? "PAUSE" : "START", lit: true, big: true) {
                    action(.timer(.toggle))
                }
                PadButton(symbol: "plus", title: "1 MIN") { action(.timer(.add(minutes: 1))) }.frame(width: 92)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var stateTitle: String {
        switch timer.state {
        case .idle: return "TIMER"
        case .running: return "RUNNING"
        case .paused: return "PAUSED"
        case .done: return "DONE"
        }
    }

    private func chip(_ title: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(HudTheme.mont(10, .black)).tracking(1.2).foregroundStyle(HudTheme.inkDim)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Color(white: 0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Captions

public struct CaptionsControls: View {
    public var captions: HudSnapshot.Captions
    public var language: String
    public var action: (PhoneAction) -> Void

    public init(captions: HudSnapshot.Captions, language: String,
                action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.captions = captions
        self.language = language
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            PadCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(captions.status).font(HudTheme.mont(10, .black)).tracking(2)
                            .foregroundStyle(captions.isListening ? HudTheme.accent : HudTheme.inkDim)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        Text(captions.isListening ? captions.elapsed : "").font(HudTheme.mont(11, .black))
                            .foregroundStyle(HudTheme.inkDim)
                    }
                    Spacer(minLength: 0)
                    let last = (captions.lines.suffix(2) + [captions.partial]).filter { !$0.isEmpty }
                    Text(last.isEmpty ? "What is said around you shows on the glasses." : last.joined(separator: " "))
                        .font(HudTheme.mont(16, .semibold))
                        .foregroundStyle(last.isEmpty ? HudTheme.inkFaint : HudTheme.ink)
                        .lineLimit(4)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            HStack(spacing: 10) {
                Menu {
                    ForEach(CaptionsEngine.languages, id: \.id) { option in
                        Button(option.name) { action(.captionsLanguage(option.id)) }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "globe").font(.system(size: 20, weight: .bold))
                        Text(language.uppercased()).font(HudTheme.mont(10, .black)).tracking(1.8)
                    }
                    .foregroundStyle(HudTheme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .frame(width: 92)
                PadButton(symbol: captions.isListening ? "stop.fill" : "mic.fill",
                          title: captions.isListening ? "STOP" : "LISTEN", lit: true, big: true) {
                    action(.captionsToggle)
                }
                PadButton(symbol: "list.bullet.rectangle", title: "SAVED") { action(.captionsSessions) }.frame(width: 92)
            }
            .frame(height: 110)
        }
    }
}

// MARK: - Note

public struct NoteControls: View {
    public var note: HudSnapshot.Note
    public var action: (PhoneAction) -> Void
    @State private var lastDrag: CGFloat = 0

    public init(note: HudSnapshot.Note, action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.note = note
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            PadCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(note.isEditing ? "WRITING" : "TELEPROMPTER").font(HudTheme.mont(10, .black))
                            .tracking(2).foregroundStyle(note.isEditing ? HudTheme.accent : HudTheme.inkDim)
                        Spacer()
                        Image(systemName: "arrow.up.and.down").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(HudTheme.inkFaint)
                    }
                    Text(note.text.isEmpty ? "Nothing written yet" : note.text)
                        .font(HudTheme.mont(16, .semibold))
                        .foregroundStyle(note.text.isEmpty ? HudTheme.inkFaint : HudTheme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                }
                .padding(18)
            }
            .contentShape(Rectangle())
            // Drag to roll the teleprompter on the glasses.
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let dy = value.translation.height - lastDrag
                    lastDrag = value.translation.height
                    action(.note(.scroll(-dy * 3)))
                }
                .onEnded { _ in lastDrag = 0 })
            HStack(spacing: 10) {
                PadButton(symbol: "trash", title: "CLEAR") { action(.note(.clear)) }.frame(width: 92)
                PadButton(symbol: note.isEditing ? "checkmark" : "pencil",
                          title: note.isEditing ? "DONE" : "WRITE", lit: true, big: true) {
                    action(.note(.write))
                }
                PadButton(symbol: "arrow.up.to.line", title: "TOP") { action(.note(.scroll(-.infinity))) }.frame(width: 92)
            }
            .frame(height: 96)
        }
    }
}

// MARK: - YouTube

public struct YouTubeControls: View {
    public enum List: Hashable, Sendable { case results, upNext, home, subscriptions, queue }

    public var youtube: HudSnapshot.YouTube
    public var scrolls: Bool
    public var action: (PhoneAction) -> Void
    /// Picked by hand; until then the list follows what is going on.
    @State private var picked: List?

    public init(youtube: HudSnapshot.YouTube, scrolls: Bool = true,
                action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.youtube = youtube
        self.scrolls = scrolls
        self.action = action
    }

    private var lists: [List] {
        var lists: [List] = []
        if !youtube.query.isEmpty { lists.append(.results) }
        if youtube.hasVideo { lists.append(.upNext) }
        lists.append(.home)
        if youtube.showsSubscriptions { lists.append(.subscriptions) }
        lists.append(.queue)
        return lists
    }

    /// Searching shows results; something playing shows what comes next.
    private var list: List {
        if let picked, lists.contains(picked) { return picked }
        return lists[0]
    }

    private func title(_ list: List) -> String {
        switch list {
        case .results: "RESULTS"
        case .upNext: "UP NEXT"
        case .home: "HOME"
        case .subscriptions: "SUBS"
        case .queue: youtube.queue.isEmpty ? "QUEUE" : "QUEUE \(youtube.queue.count)"
        }
    }

    private var videos: [YouTubeVideo] {
        switch list {
        case .results: youtube.results
        case .upNext: youtube.upNext.filter { $0.id != youtube.videoId }
        case .home: youtube.home
        case .subscriptions: youtube.subscriptions
        case .queue: youtube.queue
        }
    }

    public var body: some View {
        VStack(spacing: 8) {
            nowPlaying
            HStack(spacing: 8) {
                PadButton(symbol: "gobackward.5", title: nil) { action(.youtube(.seek(-5))) }
                PadButton(symbol: youtube.isPlaying ? "pause.fill" : "play.fill", title: nil, lit: true, big: true) {
                    action(.youtube(.togglePlay))
                }
                PadButton(symbol: "goforward.5", title: nil) { action(.youtube(.seek(5))) }
                if youtube.canSkipAd {
                    PadButton(symbol: "forward.end.fill", title: "SKIP AD", lit: true) { action(.youtube(.skipAd)) }
                } else {
                    PadButton(symbol: "forward.end.fill", title: nil) { action(.youtube(.next)) }
                }
            }
            .frame(height: 58)
            HStack(spacing: 8) {
                searchField
                if youtube.hasVideo {
                    let watching = youtube.page == .player
                    Button { action(.youtube(.page(watching ? .browse : .player))) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: watching ? "square.grid.2x2" : "play.rectangle.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(watching ? "BROWSE" : "WATCH").font(HudTheme.mont(10, .black)).tracking(1.4)
                        }
                        .foregroundStyle(watching ? HudTheme.ink : Color.black)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(watching ? Color(white: 0.14) : HudTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                ForEach(lists, id: \.self) { choice in
                    Button { picked = choice } label: {
                        Text(title(choice)).font(HudTheme.mont(10, .black)).tracking(1.2)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(choice == list ? Color.black : HudTheme.inkDim)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(choice == list ? HudTheme.accent : Color(white: 0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 30)
            rows
                .frame(maxHeight: .infinity, alignment: .top)
                .layoutPriority(-1)
        }
        .onChange(of: youtube.query) { _, _ in picked = nil }
    }

    private var nowPlaying: some View {
        PadCard {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(state).font(HudTheme.mont(10, .black)).tracking(2)
                        .foregroundStyle(youtube.isPlaying || youtube.isAd ? HudTheme.accent : HudTheme.inkDim)
                    Text(youtube.channel).font(HudTheme.mont(11, .semibold)).foregroundStyle(HudTheme.inkDim)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                if !youtube.notice.isEmpty {
                    Text(youtube.notice).font(HudTheme.mont(11, .semibold)).foregroundStyle(HudTheme.accent)
                        .lineLimit(1)
                }
                Text(youtube.hasVideo ? youtube.title : "Pick something below, or search")
                    .font(HudTheme.mont(15, youtube.hasVideo ? .black : .semibold))
                    .foregroundStyle(youtube.hasVideo ? HudTheme.ink : HudTheme.inkFaint)
                    .lineLimit(1)
                if youtube.hasVideo && !youtube.isLive {
                    HStack(spacing: 8) {
                        Text(HudSnapshot.NowPlaying.time(youtube.elapsed))
                        ProgressLine(progress: youtube.progress).frame(height: 4)
                        Text("\u{2212}" + HudSnapshot.NowPlaying.time(max(youtube.duration - youtube.elapsed, 0)))
                    }
                    .font(HudTheme.mont(10, .black)).monospacedDigit().foregroundStyle(HudTheme.inkDim)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var state: String {
        if youtube.isAd { return "AD" }
        if !youtube.hasVideo { return "YOUTUBE" }
        if youtube.isLive { return "LIVE" }
        return youtube.isPlaying ? "PLAYING" : "PAUSED"
    }

    private var searchField: some View {
        Button { action(.youtube(.search)) } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(youtube.isEditingQuery ? HudTheme.accent : HudTheme.inkDim)
                Text(youtube.query.isEmpty ? "Search YouTube" : youtube.query)
                    .font(HudTheme.mont(14, youtube.query.isEmpty ? .semibold : .black))
                    .foregroundStyle(youtube.query.isEmpty ? HudTheme.inkFaint : HudTheme.ink)
                    .lineLimit(1)
                if youtube.isEditingQuery {
                    Rectangle().fill(HudTheme.accent).frame(width: 2, height: 18)
                }
                Spacer(minLength: 0)
                if youtube.loading {
                    Text("\u{2026}").font(HudTheme.mont(14, .black)).foregroundStyle(HudTheme.inkDim)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(Color(white: 0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(youtube.isEditingQuery ? HudTheme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rows: some View {
        let videos = self.videos
        if videos.isEmpty {
            Text(emptyText).font(HudTheme.mont(13, .semibold)).foregroundStyle(HudTheme.inkFaint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if scrolls {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, video in row(video, index) }
                }
            }
            .scrollIndicators(.hidden)
        } else {
            VStack(spacing: 6) {
                ForEach(Array(videos.prefix(3).enumerated()), id: \.offset) { index, video in row(video, index) }
            }
        }
    }

    private var emptyText: String {
        if youtube.loading { return "Loading\u{2026}" }
        if !youtube.problem.isEmpty { return youtube.problem }
        return switch list {
        case .queue: "Tap + on a video to play it next"
        case .results: "Nothing found"
        default: "Nothing here yet"
        }
    }

    private func row(_ video: YouTubeVideo, _ index: Int) -> some View {
        let inQueue = list == .queue
        return HStack(spacing: 10) {
            Button {
                action(.youtube(inQueue ? .playQueued(index) : .play(video)))
            } label: {
                HStack(spacing: 10) {
                    Thumbnail(video: video, corner: 8, badge: 8).frame(width: 84, height: 47)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title).font(HudTheme.mont(12, .black)).foregroundStyle(HudTheme.ink)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text([video.channel, video.meta].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                            .font(HudTheme.mont(10, .semibold)).foregroundStyle(HudTheme.inkDim).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            let queued = youtube.queue.contains(video)
            Button {
                action(.youtube(inQueue ? .dequeue(index) : .enqueue(video)))
            } label: {
                Image(systemName: inQueue ? "xmark" : queued ? "checkmark" : "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(queued && !inQueue ? Color.black : HudTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(queued && !inQueue ? HudTheme.accent : Color(white: 0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(queued && !inQueue)
        }
        .frame(height: 52)
    }
}

// MARK: - The app's pad

/// The fullscreen app's controls, by kind.
public struct AppPad: View {
    public var kind: HudPanelKind
    public var snapshot: HudSnapshot
    public var captionsLanguage: String
    public var scrolls: Bool
    public var action: (PhoneAction) -> Void

    public init(kind: HudPanelKind, snapshot: HudSnapshot, captionsLanguage: String = "pt-BR",
                scrolls: Bool = true, action: @escaping (PhoneAction) -> Void = { _ in }) {
        self.scrolls = scrolls
        self.kind = kind
        self.snapshot = snapshot
        self.captionsLanguage = captionsLanguage
        self.action = action
    }

    public var body: some View {
        Group {
            switch kind {
            case .sky:
                SkyControls(sky: snapshot.sky, overhead: snapshot.overhead, view: snapshot.skyView,
                            heading: snapshot.minimap.heading, scrolls: scrolls, action: action)
            case .music: MusicControls(music: snapshot.music, action: action)
            case .clock: TimerControls(timer: snapshot.timer, action: action)
            case .captions: CaptionsControls(captions: snapshot.captions, language: captionsLanguage, action: action)
            case .note: NoteControls(note: snapshot.note, action: action)
            case .youtube: YouTubeControls(youtube: snapshot.youtube, scrolls: scrolls, action: action)
            default: Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
