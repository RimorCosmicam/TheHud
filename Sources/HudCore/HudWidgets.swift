import SwiftUI

// The widgets, each drawn for one slot: 400 by about 300 points, three down each side of the
// glasses. Held up alone, each becomes its app (HudApps, HudWidgetApps).
//
// The floor for text is about 24px, half a degree through the birdbath; labels go a little
// under it only where they are a word of context beside something larger.

/// The small label at the top of a widget.
struct WidgetLabel: View {
    var text: String
    var accent = false
    var body: some View {
        Text(text).font(HudTheme.mont(16, .black)).tracking(3)
            .foregroundStyle(accent ? HudTheme.accent : HudTheme.inkDim)
            .lineLimit(1)
    }
}

extension View {
    /// The widget's own surface, filling its slot.
    func widgetSurface(padding: CGFloat = 26) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(HudTheme.surface,
                        in: RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
                .strokeBorder(HudTheme.edge, lineWidth: 1))
    }
}

// MARK: - Clock

public struct ClockWidget: View {
    public var clock: HudSnapshot.Clock
    public var timer: HudSnapshot.TimerReading
    public init(_ clock: HudSnapshot.Clock, timer: HudSnapshot.TimerReading = .init()) {
        self.clock = clock
        self.timer = timer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(clock.time).font(HudTheme.mont(112, .black)).tracking(-4)
                if let meridiem = clock.meridiem {
                    Text(meridiem).font(HudTheme.mont(30, .black))
                }
            }
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(HudTheme.ink)
            .padding(.top, -12)

            Text("\(clock.weekday)  \u{00B7}  \(clock.date)")
                .font(HudTheme.mont(19, .black)).tracking(2.5)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(HudTheme.inkDim)

            Spacer(minLength: 10)

            // A running timer outranks the calendar: it is the thing with a deadline.
            if timer.state != .idle {
                row(mark: HudTheme.accent, label: timer.state == .done ? "TIME'S UP" : "TIMER",
                    title: timer.state == .paused ? "Paused" : (timer.isStopwatch ? "Stopwatch" : "Running"),
                    trailing: timer.text)
            } else if let event = clock.nextEvent {
                row(mark: HudTheme.accent, label: "NEXT", title: event,
                    trailing: clock.nextEventTime)
            }
        }
        .widgetSurface()
    }

    private func row(mark: Color, label: String, title: String, trailing: String?) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1).fill(mark).frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(HudTheme.mont(14, .black)).tracking(3)
                    .foregroundStyle(HudTheme.inkDim)
                Text(title).font(HudTheme.mont(24, .black)).lineLimit(1)
                    .foregroundStyle(HudTheme.ink)
            }
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing).font(HudTheme.mont(28, .black)).monospacedDigit()
                    .foregroundStyle(HudTheme.ink)
            }
        }
    }
}

// MARK: - Weather

public struct WeatherWidget: View {
    public var weather: HudSnapshot.Weather?
    public init(_ weather: HudSnapshot.Weather?) { self.weather = weather }

    public var body: some View {
        Group {
            if let weather {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(weather.temperature)")
                                .font(HudTheme.mont(84, .black)).tracking(-3)
                            Text("\u{00B0}").font(HudTheme.mont(50, .black))
                        }
                        .foregroundStyle(HudTheme.ink)
                        .padding(.top, -10)
                        Spacer(minLength: 0)
                        Image(systemName: weather.symbol)
                            .font(.system(size: 50, weight: .light))
                            .foregroundStyle(HudTheme.ink)
                    }
                    Text(weather.condition)
                        .font(HudTheme.mont(20, .black)).tracking(3)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(HudTheme.ink)
                    Text("H \(weather.high)\u{00B0}  L \(weather.low)\u{00B0}  \u{00B7}  \(weather.place)")
                        .font(HudTheme.mont(15, .black)).tracking(2)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(HudTheme.inkDim)
                        .padding(.top, 4)
                    Spacer(minLength: 8)
                    hours(weather)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetLabel(text: "WEATHER")
                    Text("Waiting for a reading").font(HudTheme.mont(24, .semibold))
                        .foregroundStyle(HudTheme.inkDim)
                }
            }
        }
        .widgetSurface()
    }

    /// The next four hours, so the slot answers "will it rain on the way".
    private func hours(_ weather: HudSnapshot.Weather) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(weather.hourly.dropFirst().prefix(4).enumerated()), id: \.offset) { _, hour in
                VStack(spacing: 4) {
                    Text(hour.label).font(HudTheme.mont(14, .black)).tracking(1)
                        .foregroundStyle(HudTheme.inkDim)
                    Image(systemName: hour.symbol).font(.system(size: 20, weight: .light))
                        .frame(height: 24)
                    Text("\(hour.temperature)\u{00B0}").font(HudTheme.mont(20, .black))
                }
                .foregroundStyle(HudTheme.ink)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Map

/// The small map: the whole slot is map, with the place and speed laid over its top edge.
public struct MapWidget: View {
    public var minimap: HudSnapshot.Minimap
    public var ground: Image?
    public var proceduralGround: Bool
    public init(_ minimap: HudSnapshot.Minimap, ground: Image?, proceduralGround: Bool) {
        self.minimap = minimap
        self.ground = ground
        self.proceduralGround = proceduralGround
    }

    public var body: some View {
        MinimapPanel(minimap, ground: ground, proceduralGround: proceduralGround,
                     showsHeader: false)
            .overlay(alignment: .top) {
                HStack {
                    Text(minimap.place).font(HudTheme.mont(17, .black)).tracking(2.5)
                        .foregroundStyle(HudTheme.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(minimap.speed).font(HudTheme.mont(16, .black)).tracking(2)
                        .foregroundStyle(HudTheme.inkDim)
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 30)
                .background(LinearGradient(colors: [.black.opacity(0.85), .clear],
                                           startPoint: .top, endPoint: .bottom))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: HudTheme.cornerRadius,
                                                  topTrailingRadius: HudTheme.cornerRadius,
                                                  style: .continuous))
            }
    }
}

// MARK: - Activity

/// A ring that fills toward the day's goal.
struct ProgressRing: View {
    var fraction: Double
    var lineWidth: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(fraction, 0.001))
                .stroke(HudTheme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

public struct ActivityWidget: View {
    public var activity: HudSnapshot.Activity?
    public init(_ activity: HudSnapshot.Activity?) { self.activity = activity }

    public var body: some View {
        Group {
            if let activity {
                HStack(spacing: 26) {
                    ZStack {
                        ProgressRing(fraction: activity.fraction, lineWidth: 18)
                        VStack(spacing: 2) {
                            Image(systemName: "figure.walk").font(.system(size: 34, weight: .medium))
                            Text("\(Int(activity.fraction * 100))%")
                                .font(HudTheme.mont(22, .black))
                        }
                        .foregroundStyle(HudTheme.ink)
                    }
                    .frame(width: 160, height: 160)

                    VStack(alignment: .leading, spacing: 4) {
                        WidgetLabel(text: "STEPS")
                        Text(activity.steps.formatted())
                            .font(HudTheme.mont(48, .black)).tracking(-1)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(HudTheme.ink)
                        if let km = activity.distanceKm {
                            stat(String(format: "%.1f", km), "KM")
                        }
                        if let floors = activity.floors {
                            stat("\(floors)", floors == 1 ? "FLOOR" : "FLOORS")
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetLabel(text: "ACTIVITY")
                    Text("Counting steps needs Motion & Fitness access")
                        .font(HudTheme.mont(22, .semibold)).foregroundStyle(HudTheme.inkDim)
                }
            }
        }
        .widgetSurface()
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(HudTheme.mont(26, .black)).foregroundStyle(HudTheme.ink)
            Text(unit).font(HudTheme.mont(15, .black)).tracking(2).foregroundStyle(HudTheme.inkDim)
        }
    }
}

// MARK: - Sky

public struct SkyWidget: View {
    public var sky: HudSnapshot.Sky
    public init(_ sky: HudSnapshot.Sky) { self.sky = sky }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                WidgetLabel(text: sky.dayProgress == nil ? "TONIGHT" : "TODAY")
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: sky.moonSymbol).font(.system(size: 40, weight: .light))
                        .foregroundStyle(HudTheme.ink)
                    Text("\(sky.moonIllumination)%").font(HudTheme.mont(16, .black))
                        .foregroundStyle(HudTheme.inkDim)
                }
            }
            DayArc(progress: sky.dayProgress, sunAltitude: sky.sunAltitude)
                .frame(height: 104)
                .padding(.top, -24)
            HStack(spacing: 0) {
                time("arrow.up", sky.sunrise)
                Spacer(minLength: 4)
                time("camera.filters", sky.goldenHour, accent: true)
                Spacer(minLength: 4)
                time("arrow.down", sky.sunset)
            }
            .padding(.top, 10)
            Spacer(minLength: 4)
            Text(sky.hasLocation ? sky.moonPhase : "WAITING FOR A LOCATION")
                .font(HudTheme.mont(16, .black)).tracking(2.5)
                .foregroundStyle(HudTheme.inkDim).lineLimit(1)
        }
        .widgetSurface()
    }

    private func time(_ symbol: String, _ text: String?, accent: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent ? HudTheme.accent : HudTheme.inkDim)
            Text(text ?? "--").font(HudTheme.mont(20, .black)).foregroundStyle(HudTheme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// The sun's path from sunrise to sunset as an arc over a horizon line, with the sun on it.
struct DayArc: View {
    var progress: Double?
    var sunAltitude: Double

    var body: some View {
        Canvas { context, size in
            let horizon = size.height - 8
            let left = CGPoint(x: 8, y: horizon), right = CGPoint(x: size.width - 8, y: horizon)
            let peak = CGPoint(x: size.width / 2, y: horizon - (size.height - 20) * 2)
            func point(_ t: Double) -> CGPoint {
                let t = CGFloat(t)
                let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
                return CGPoint(x: a * left.x + b * peak.x + c * right.x,
                               y: a * left.y + b * peak.y + c * right.y)
            }
            var arc = Path()
            arc.move(to: left)
            arc.addQuadCurve(to: right, control: peak)
            context.stroke(arc, with: .color(.white.opacity(0.25)),
                           style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
            var line = Path()
            line.move(to: CGPoint(x: 0, y: horizon))
            line.addLine(to: CGPoint(x: size.width, y: horizon))
            context.stroke(line, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
            if let progress {
                // The part of the day already gone, drawn solid.
                var done = Path()
                done.move(to: left)
                for step in 1...40 { done.addLine(to: point(progress * Double(step) / 40)) }
                context.stroke(done, with: .color(HudTheme.accent.opacity(0.8)), lineWidth: 3)
                let sun = point(progress)
                context.fill(Path(ellipseIn: CGRect(x: sun.x - 13, y: sun.y - 13, width: 26, height: 26)),
                             with: .color(HudTheme.accent))
            } else {
                // Night: the sun is under the horizon, and as deep as it is.
                let depth = CGFloat(min(max(-sunAltitude, 0), 18) / 18)
                let sun = CGPoint(x: size.width / 2, y: horizon + 4 + depth * 6)
                context.stroke(Path(ellipseIn: CGRect(x: sun.x - 9, y: sun.y - 9, width: 18, height: 18)),
                               with: .color(HudTheme.accent.opacity(0.5)), lineWidth: 2)
            }
        }
    }
}

// MARK: - Music

/// Where Now Playing's buttons are, for drawing and for clicks.
public enum MusicLayout {
    public enum Control: CaseIterable, Sendable { case previous, playPause, next }

    /// The three buttons along the bottom of the slot, or big under the title in the app.
    public static func buttons(in size: CGSize, large: Bool) -> [(Control, CGRect)] {
        let width: CGFloat = large ? 150 : 76
        let height: CGFloat = large ? 110 : 56
        let spacing: CGFloat = large ? 28 : 12
        let total = width * 3 + spacing * 2
        let x0 = large ? 700 : (size.width - total) / 2
        let y = large ? 640 : size.height - 26 - height
        return Control.allCases.enumerated().map { index, control in
            (control, CGRect(x: x0 + CGFloat(index) * (width + spacing), y: y,
                             width: width, height: height))
        }
    }

    public static func control(at point: CGPoint, in size: CGSize, large: Bool) -> Control? {
        buttons(in: size, large: large).first { $0.1.contains(point) }?.0
    }
}

struct MusicButton: View {
    var control: MusicLayout.Control
    var isPlaying: Bool
    var large: Bool
    var hovered: Bool
    var body: some View {
        let symbol: String
        switch control {
        case .previous: symbol = "backward.fill"
        case .next: symbol = "forward.fill"
        case .playPause: symbol = isPlaying ? "pause.fill" : "play.fill"
        }
        return Image(systemName: symbol)
            .font(.system(size: large ? 54 : 26, weight: .bold))
            .foregroundStyle(control == .playPause ? Color.black : HudTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(control == .playPause ? HudTheme.accent
                        : Color.white.opacity(hovered ? 0.2 : 0.08),
                        in: RoundedRectangle(cornerRadius: large ? 30 : 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: large ? 30 : 16, style: .continuous)
                .strokeBorder(hovered ? Color.white.opacity(0.7) : .clear, lineWidth: 2))
    }
}

public struct MusicWidget: View {
    public var music: HudSnapshot.NowPlaying?
    public var artwork: Image?
    /// The cursor, in the widget's own points.
    public var hover: CGPoint?
    public init(_ music: HudSnapshot.NowPlaying?, artwork: Image?, hover: CGPoint? = nil) {
        self.music = music
        self.artwork = artwork
        self.hover = hover
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 18) {
                    Artwork(image: artwork, corner: 14).frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 4) {
                        WidgetLabel(text: music?.isPlaying == true ? "NOW PLAYING" : "MUSIC",
                                    accent: music?.isPlaying == true)
                        Text(music?.title ?? "Nothing playing")
                            .font(HudTheme.mont(24, .black)).lineLimit(2)
                            .foregroundStyle(HudTheme.ink)
                        Text(music?.artist ?? "Play something in Music")
                            .font(HudTheme.mont(18, .semibold)).lineLimit(1)
                            .foregroundStyle(HudTheme.inkDim)
                    }
                }
                .padding(26)

                if let music {
                    ProgressLine(progress: music.progress)
                        .frame(width: size.width - 52, height: 4)
                        .offset(x: 26, y: size.height - 26 - 56 - 22)
                }
                ForEach(MusicLayout.buttons(in: size, large: false), id: \.0) { control, frame in
                    MusicButton(control: control, isPlaying: music?.isPlaying ?? false,
                                large: false, hovered: hover.map(frame.contains) ?? false)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .widgetSurface(padding: 0)
    }
}

struct ProgressLine: View {
    var progress: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(HudTheme.ink).frame(width: geometry.size.width * progress)
            }
        }
    }
}

struct Artwork: View {
    var image: Image?
    var corner: CGFloat
    var body: some View {
        ZStack {
            Color.white.opacity(0.07)
            if let image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: 44, weight: .light))
                    .foregroundStyle(HudTheme.inkDim)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Note

public struct NoteWidget: View {
    public var note: HudSnapshot.Note
    public init(_ note: HudSnapshot.Note) { self.note = note }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetLabel(text: note.isEditing ? "WRITING" : "NOTE", accent: note.isEditing)
            if note.text.isEmpty && !note.isEditing {
                Text("Click to write a note").font(HudTheme.mont(24, .semibold))
                    .foregroundStyle(HudTheme.inkFaint)
            } else {
                (Text(note.text) + Text(note.isEditing ? "|" : "").foregroundColor(HudTheme.accent))
                    .font(HudTheme.mont(24, .semibold))
                    .lineSpacing(4)
                    .foregroundStyle(HudTheme.ink)
                    .lineLimit(6)
                    .truncationMode(.head)
            }
        }
        .widgetSurface()
    }
}

// MARK: - Captions

public struct CaptionsWidget: View {
    public var captions: HudSnapshot.Captions
    public init(_ captions: HudSnapshot.Captions) { self.captions = captions }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel(text: "CAPTIONS")
                Spacer()
                Text(captions.isListening ? captions.elapsed : "")
                    .font(HudTheme.mont(16, .black)).foregroundStyle(HudTheme.inkDim)
                Text(captions.status).font(HudTheme.mont(14, .black)).tracking(2)
                    .foregroundStyle(captions.isListening ? HudTheme.accent : HudTheme.inkFaint)
            }
            Spacer(minLength: 8)
            if captions.isListening || !captions.lines.isEmpty {
                CaptionLines(captions: captions, size: 23, count: 5)
            } else {
                Text("Click to start listening").font(HudTheme.mont(24, .semibold))
                    .foregroundStyle(HudTheme.inkFaint)
                Spacer(minLength: 0)
            }
        }
        .widgetSurface()
    }
}

/// The last few lines of a transcript, newest at the bottom and brightest.
struct CaptionLines: View {
    var captions: HudSnapshot.Captions
    var size: CGFloat
    var count: Int
    var body: some View {
        let lines = Array(captions.lines.suffix(captions.partial.isEmpty ? count : count - 1))
        VStack(alignment: .leading, spacing: size * 0.3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let age = lines.count - index
                Text(line).foregroundStyle(Color.white.opacity(max(0.95 - Double(age) * 0.15, 0.35)))
            }
            if !captions.partial.isEmpty {
                Text(captions.partial).foregroundStyle(HudTheme.accent)
            }
        }
        .font(HudTheme.mont(size, .semibold))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
    }
}
