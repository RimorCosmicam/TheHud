import SwiftUI

// The newer widgets held up alone, each on the canvas inside the safe inset (1792 x 952).
// Positions inside are fixed numbers, as in the Maps app, so clicks can be worked out without
// a view: see `MusicLayout` and `ClockAppLayout`.

extension View {
    func appSurface() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(HudTheme.surface,
                        in: RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
                .strokeBorder(HudTheme.edge, lineWidth: 1))
    }

    /// Puts a view at a rect inside the app.
    func at(_ rect: CGRect, alignment: Alignment = .topLeading) -> some View {
        frame(width: rect.width, height: rect.height, alignment: alignment)
            .offset(x: rect.minX, y: rect.minY)
    }
}

// MARK: - Activity

public struct ActivityApp: View {
    public var activity: HudSnapshot.Activity?
    public init(_ activity: HudSnapshot.Activity?) { self.activity = activity }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if let activity {
                ZStack {
                    ProgressRing(fraction: activity.fraction, lineWidth: 44)
                    VStack(spacing: 6) {
                        Text(activity.steps.formatted()).font(HudTheme.mont(110, .black))
                            .tracking(-3).lineLimit(1).minimumScaleFactor(0.5)
                        Text("OF \(activity.goal.formatted()) STEPS").font(HudTheme.mont(24, .black))
                            .tracking(3).foregroundStyle(HudTheme.inkDim)
                    }
                    .foregroundStyle(HudTheme.ink)
                    .padding(80)
                }
                .at(CGRect(x: 90, y: 156, width: 640, height: 640))

                HStack(spacing: 0) {
                    stat("DISTANCE", activity.distanceKm.map { String(format: "%.1f KM", $0) } ?? "--")
                    stat("FLOORS", activity.floors.map(String.init) ?? "--")
                    stat("GOAL", "\(Int(activity.fraction * 100))%")
                }
                .at(CGRect(x: 820, y: 150, width: 900, height: 120))

                hours(activity.hourly)
                    .at(CGRect(x: 820, y: 420, width: 900, height: 400))
            } else {
                Text("Counting steps needs Motion & Fitness access in Settings")
                    .font(HudTheme.mont(34, .semibold)).foregroundStyle(HudTheme.inkDim)
                    .at(CGRect(x: 0, y: 0, width: 1792, height: 952), alignment: .center)
            }
        }
        .appSurface()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).hudLabel()
            Text(value).font(HudTheme.mont(56, .black)).foregroundStyle(HudTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hours(_ hourly: [Int]) -> some View {
        let peak = max(hourly.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 16) {
            Text("BY THE HOUR").hudLabel()
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<24, id: \.self) { hour in
                    let steps = hour < hourly.count ? hourly[hour] : 0
                    let current = hour == hourly.count - 1
                    RoundedRectangle(cornerRadius: 5)
                        .fill(current ? HudTheme.accent : Color.white.opacity(steps > 0 ? 0.55 : 0.1))
                        .frame(height: max(CGFloat(steps) / CGFloat(peak) * 260, 6))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 270, alignment: .bottom)
            HStack {
                ForEach(["0", "6", "12", "18", "24"], id: \.self) { label in
                    Text(label).font(HudTheme.mont(18, .black)).foregroundStyle(HudTheme.inkFaint)
                    if label != "24" { Spacer() }
                }
            }
        }
    }
}

// MARK: - Sky

/// The sky overhead as a dome: the horizon is the rim, straight up is the centre, and the
/// direction the phone faces is at the top, so it can be held against the real sky.
public struct SkyApp: View {
    public var sky: HudSnapshot.Sky
    public var heading: Double
    public init(_ sky: HudSnapshot.Sky, heading: Double) {
        self.sky = sky
        self.heading = heading
    }

    static let centre = CGPoint(x: 896, y: 476)
    static let radius: CGFloat = 430

    public var body: some View {
        ZStack(alignment: .topLeading) {
            chart.frame(width: 1792, height: 952)
            sunAndMoon.at(CGRect(x: 52, y: 52, width: 380, height: 848))
            planets.at(CGRect(x: 1360, y: 52, width: 380, height: 848))
        }
        .appSurface()
    }

    private func project(az: Double, alt: Double) -> CGPoint? {
        guard alt > -0.5 else { return nil }
        let zenith = (90 - min(alt, 90)) * .pi / 180
        let r = Self.radius * CGFloat(tan(zenith / 2))
        let angle = (az - heading) * .pi / 180
        return CGPoint(x: Self.centre.x + r * CGFloat(sin(angle)),
                       y: Self.centre.y - r * CGFloat(cos(angle)))
    }

    private var daylight: Bool { sky.sunAltitude > -6 }

    private var chart: some View {
        Canvas { context, _ in
            let c = Self.centre, R = Self.radius
            let dome = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
            context.stroke(dome, with: .color(.white.opacity(0.3)), lineWidth: 2)
            for altitude in [30.0, 60.0] {
                let r = R * CGFloat(tan((90 - altitude) * .pi / 360))
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity(0.07)), lineWidth: 1)
            }
            // The compass round the rim.
            for (index, name) in ["N", "NE", "E", "SE", "S", "SW", "W", "NW"].enumerated() {
                let angle = (Double(index) * 45 - heading) * .pi / 180
                let r = R + 30
                let p = CGPoint(x: c.x + r * CGFloat(sin(angle)), y: c.y - r * CGFloat(cos(angle)))
                context.draw(Text(name).font(HudTheme.mont(index % 2 == 0 ? 24 : 16, .black))
                    .foregroundColor(name == "N" ? HudTheme.accent : HudTheme.inkDim), at: p)
            }
            let starOpacity = daylight ? 0.35 : 1.0
            // Constellation figures, cut where they go under the horizon.
            for line in sky.lines {
                var path = Path()
                var drawing = false
                for point in line {
                    if let p = project(az: Double(point.az), alt: Double(point.alt)) {
                        if drawing { path.addLine(to: p) } else { path.move(to: p) }
                        drawing = true
                    } else {
                        drawing = false
                    }
                }
                context.stroke(path, with: .color(.white.opacity(0.2 * starOpacity)), lineWidth: 1.2)
            }
            for star in sky.stars {
                guard let p = project(az: Double(star.az), alt: Double(star.alt)) else { continue }
                let r = CGFloat(min(max(4.4 - 0.75 * Double(star.mag), 0.9), 5.5))
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(Self.colour(bv: star.bv).opacity(starOpacity)))
            }
            for label in sky.constellations {
                guard let p = project(az: Double(label.az), alt: Double(label.alt)) else { continue }
                context.draw(Text(label.name).font(HudTheme.mont(13, .black))
                    .foregroundColor(.white.opacity(0.32 * starOpacity)), at: p)
            }
            for label in sky.starNames {
                guard let p = project(az: Double(label.az), alt: Double(label.alt)) else { continue }
                context.draw(Text(label.name).font(HudTheme.mont(15, .semibold))
                    .foregroundColor(.white.opacity(0.6 * starOpacity)),
                             at: CGPoint(x: p.x + 10, y: p.y - 12), anchor: .leading)
            }
            for body in sky.bodies {
                guard let p = project(az: body.az, alt: body.alt) else { continue }
                switch body.kind {
                case .sun:
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)),
                                 with: .color(HudTheme.accent))
                case .moon:
                    let moon = context.resolve(Image(systemName: sky.moonSymbol))
                    context.draw(moon, in: CGRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40))
                case .planet:
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
                                 with: .color(HudTheme.accent))
                    context.draw(Text(body.name).font(HudTheme.mont(16, .black))
                        .foregroundColor(HudTheme.accent),
                                 at: CGPoint(x: p.x + 12, y: p.y), anchor: .leading)
                }
            }
        }
    }

    /// A star's tint from its colour index: blue-white to orange, kept pale.
    static func colour(bv: Float) -> Color {
        let t = Double(min(max((bv + 0.3) / 2.0, 0), 1))
        return Color(red: 0.78 + 0.22 * t, green: 0.86 - 0.06 * t, blue: 1.0 - 0.4 * t)
    }

    private var sunAndMoon: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SUN").hudLabel()
            line("arrow.up", "RISE", sky.sunrise)
            line("camera.filters", "GOLDEN", sky.goldenHour)
            line("arrow.down", "SET", sky.sunset)
            Spacer().frame(height: 30)
            Text("MOON").hudLabel()
            HStack(spacing: 16) {
                Image(systemName: sky.moonSymbol).font(.system(size: 64, weight: .light))
                VStack(alignment: .leading, spacing: 4) {
                    Text(sky.moonPhase).font(HudTheme.mont(22, .black))
                    Text("\(sky.moonIllumination)% LIT").font(HudTheme.mont(18, .black))
                        .foregroundStyle(HudTheme.inkDim)
                }
            }
            .foregroundStyle(HudTheme.ink)
            line("arrow.up", "RISE", sky.moonrise)
            line("arrow.down", "SET", sky.moonset)
            Spacer()
            if daylight {
                Text("DAYLIGHT \u{00B7} STARS FAINT").font(HudTheme.mont(16, .black)).tracking(2)
                    .foregroundStyle(HudTheme.inkFaint)
            }
        }
    }

    private func line(_ symbol: String, _ label: String, _ value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                .foregroundStyle(HudTheme.inkDim).frame(width: 26)
            Text(label).font(HudTheme.mont(17, .black)).tracking(2.5)
                .foregroundStyle(HudTheme.inkDim).frame(width: 110, alignment: .leading)
            Text(value ?? "--").font(HudTheme.mont(30, .black)).foregroundStyle(HudTheme.ink)
        }
    }

    private var planets: some View {
        let up = sky.bodies.filter { $0.kind == .planet && $0.alt > 0 }
        return VStack(alignment: .trailing, spacing: 18) {
            Text("FACING").hudLabel()
            Text(SkyModel.compass(heading)).font(HudTheme.mont(60, .black))
                .foregroundStyle(HudTheme.ink)
            Spacer().frame(height: 20)
            Text("PLANETS UP").hudLabel()
            if up.isEmpty {
                Text("None right now").font(HudTheme.mont(24, .semibold))
                    .foregroundStyle(HudTheme.inkDim)
            }
            ForEach(Array(up.enumerated()), id: \.offset) { _, body in
                HStack(spacing: 14) {
                    Text(body.name).font(HudTheme.mont(24, .black)).foregroundStyle(HudTheme.accent)
                    Spacer()
                    Text("\(SkyModel.compass(body.az))  \(Int(body.alt.rounded()))\u{00B0}")
                        .font(HudTheme.mont(24, .black)).foregroundStyle(HudTheme.ink)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Music

public struct MusicApp: View {
    public var music: HudSnapshot.NowPlaying?
    public var artwork: Image?
    public var hover: CGPoint?
    public init(_ music: HudSnapshot.NowPlaying?, artwork: Image?, hover: CGPoint?) {
        self.music = music
        self.artwork = artwork
        self.hover = hover
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Artwork(image: artwork, corner: 36)
                .at(CGRect(x: 72, y: 136, width: 560, height: 560))

            VStack(alignment: .leading, spacing: 14) {
                Text(music?.isPlaying == true ? "NOW PLAYING" : "MUSIC").font(HudTheme.mont(20, .black))
                    .tracking(4).foregroundStyle(music?.isPlaying == true ? HudTheme.accent : HudTheme.inkDim)
                Text(music?.title ?? "Nothing playing").font(HudTheme.mont(68, .black))
                    .lineLimit(2).foregroundStyle(HudTheme.ink)
                Text(music?.artist ?? "Play something in the Music app")
                    .font(HudTheme.mont(36, .semibold)).foregroundStyle(HudTheme.ink.opacity(0.85))
                    .lineLimit(1)
                if let album = music?.album, !album.isEmpty {
                    Text(album).font(HudTheme.mont(26, .semibold)).foregroundStyle(HudTheme.inkDim)
                        .lineLimit(1)
                }
            }
            .at(CGRect(x: 700, y: 140, width: 1020, height: 360), alignment: .bottomLeading)

            if let music {
                VStack(spacing: 12) {
                    ProgressLine(progress: music.progress).frame(height: 8)
                    HStack {
                        Text(HudSnapshot.NowPlaying.time(music.elapsed))
                        Spacer()
                        Text("\u{2212}" + HudSnapshot.NowPlaying.time(max(music.duration - music.elapsed, 0)))
                    }
                    .font(HudTheme.mont(22, .black)).monospacedDigit()
                    .foregroundStyle(HudTheme.inkDim)
                }
                .at(CGRect(x: 700, y: 540, width: 1020, height: 60))
            }

            ForEach(MusicLayout.buttons(in: CGSize(width: 1792, height: 952), large: true), id: \.0) { control, frame in
                MusicButton(control: control, isPlaying: music?.isPlaying ?? false, large: true,
                            hovered: hover.map(frame.contains) ?? false)
                    .at(frame)
            }
        }
        .appSurface()
    }
}

// MARK: - Note

/// The note, large: a teleprompter. Scrolling moves it; a click edits it.
public struct NoteApp: View {
    public var note: HudSnapshot.Note
    public init(_ note: HudSnapshot.Note) { self.note = note }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            WidgetLabel(text: note.isEditing ? "WRITING" : "NOTE", accent: note.isEditing)
                .at(CGRect(x: 72, y: 56, width: 600, height: 30))
            Group {
                if note.text.isEmpty && !note.isEditing {
                    Text("Click to write a note").foregroundStyle(HudTheme.inkFaint)
                } else {
                    (Text(note.text) + Text(note.isEditing ? "|" : "").foregroundColor(HudTheme.accent))
                        .foregroundStyle(HudTheme.ink)
                }
            }
            .font(HudTheme.mont(64, .semibold))
            .lineSpacing(14)
            .frame(width: 1560, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: 116, y: 120 - note.scroll)
        }
        .clipped()
        .appSurface()
    }
}

// MARK: - Captions

public struct CaptionsApp: View {
    public var captions: HudSnapshot.Captions
    public init(_ captions: HudSnapshot.Captions) { self.captions = captions }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 18) {
                WidgetLabel(text: "CAPTIONS")
                Spacer()
                Text(captions.isListening ? captions.elapsed : "")
                    .font(HudTheme.mont(22, .black)).foregroundStyle(HudTheme.inkDim)
                Text(captions.isListening ? captions.status : captions.status + " \u{00B7} CLICK TO START")
                    .font(HudTheme.mont(20, .black)).tracking(3)
                    .foregroundStyle(captions.isListening ? HudTheme.accent : HudTheme.inkFaint)
            }
            .at(CGRect(x: 72, y: 52, width: 1648, height: 40))

            CaptionLines(captions: captions, size: 54, count: 7)
                .at(CGRect(x: 120, y: 120, width: 1552, height: 760), alignment: .bottomLeading)
        }
        .appSurface()
    }
}
