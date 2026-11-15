import SwiftUI

// The glasses are about 46 degrees across at 1920 wide, so roughly 42 pixels to a degree. Text
// under about half a degree is work to read through a birdbath, which puts the floor near 24px
// and makes everything here larger than it would be on a phone. Nothing is sized by eye against
// the preview on a monitor; it is sized against that number.

/// The time, the date, and the next thing in the calendar.
public struct ClockPanel: View {
    public var clock: HudSnapshot.Clock
    public init(_ clock: HudSnapshot.Clock) { self.clock = clock }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(clock.time)
                    .font(HudTheme.mont(132, .black))
                    .tracking(-4)
                if let meridiem = clock.meridiem {
                    Text(meridiem).font(HudTheme.mont(38, .black)).tracking(1)
                }
            }
            .lineLimit(1)
            // The time is the one thing on the HUD that must never reflow.
            .minimumScaleFactor(0.5)
            .foregroundStyle(HudTheme.ink)

            Text("\(clock.weekday)  \u{00B7}  \(clock.date)")
                .font(HudTheme.mont(24, .black))
                .tracking(3.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(HudTheme.inkDim)
                .padding(.top, 6)

            if let event = clock.nextEvent {
                Divider().overlay(.white.opacity(0.14)).padding(.vertical, 18)
                HStack(spacing: 14) {
                    // The one mark that carries state, in MiniMate's Mustard.
                    RoundedRectangle(cornerRadius: 1).fill(HudTheme.accent).frame(width: 4, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT").font(HudTheme.mont(16, .black)).tracking(3)
                            .foregroundStyle(HudTheme.inkDim)
                        Text(event).font(HudTheme.mont(26, .black)).tracking(0.5)
                            .foregroundStyle(HudTheme.ink).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let time = clock.nextEventTime {
                        Text(time).font(HudTheme.mont(30, .black)).tracking(0.5)
                            .foregroundStyle(HudTheme.ink)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(padding: 34)
    }
}

/// Temperature, condition, the day's range.
public struct WeatherPanel: View {
    public var weather: HudSnapshot.Weather
    public init(_ weather: HudSnapshot.Weather) { self.weather = weather }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(weather.temperature)")
                        .font(HudTheme.mont(96, .black)).tracking(-3)
                    Text("\u{00B0}").font(HudTheme.mont(60, .black))
                }
                .foregroundStyle(HudTheme.ink)

                Spacer(minLength: 0)

                Image(systemName: weather.symbol)
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(HudTheme.ink)
                    .padding(.top, 14)
            }

            Text(weather.condition)
                .font(HudTheme.mont(24, .black)).tracking(3.5)
                .foregroundStyle(HudTheme.ink)
                .padding(.top, 2)

            HStack(spacing: 20) {
                Text("H \(weather.high)\u{00B0}")
                Text("L \(weather.low)\u{00B0}")
                Spacer(minLength: 0)
                Text(weather.place)
            }
            .font(HudTheme.mont(18, .black)).tracking(2.5)
            .foregroundStyle(HudTheme.inkDim)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(padding: 34)
    }
}

/// A moving map.
///
/// `ground` is an `MKMapSnapshotter` raster when one has arrived. Without it the streets are
/// drawn procedurally, which keeps the preview working offline and CI deterministic. Either way
/// the overlays above are the same — the route, the heading cone, the scale and the north mark —
/// so a slow or failed snapshot costs detail, not the panel.
public struct MinimapPanel: View {
    public var minimap: HudSnapshot.Minimap
    public var ground: Image?
    /// Draw made-up streets while there is no raster. Right for a still, wrong on a face.
    public var proceduralGround: Bool
    /// The place and speed above the map. The Maps app draws its own.
    public var showsHeader: Bool

    public init(_ minimap: HudSnapshot.Minimap, ground: Image? = nil,
                proceduralGround: Bool = true, showsHeader: Bool = true) {
        self.minimap = minimap
        self.ground = ground
        self.proceduralGround = proceduralGround
        self.showsHeader = showsHeader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HStack {
                    Text(minimap.place).font(HudTheme.mont(20, .black)).tracking(3)
                        .foregroundStyle(HudTheme.ink)
                    Spacer()
                    Text(minimap.speed).font(HudTheme.mont(18, .black)).tracking(2)
                        .foregroundStyle(HudTheme.inkDim)
                }
                .padding(.horizontal, 24)
                .frame(height: 58)
            }

            GeometryReader { geometry in
                ZStack {
                    if let ground {
                        groundLayer(ground, size: geometry.size)
                        // The snapshot is brighter than the rest of the HUD, and on a birdbath
                        // display brightness is what you see through. Knock it back.
                        Color.black.opacity(0.45)
                    } else if !proceduralGround {
                        Color.white.opacity(0.04)
                    } else {
                        streets(size: geometry.size)
                        // The route is decorative, and only honest over decorative streets. Over
                        // a real map a made-up line cuts through real buildings, so it waits
                        // until there is actual routing to draw.
                        route(size: geometry.size)
                    }
                    // The edge fades into the dark rather than stopping at a hard line: on a
                    // see-through display a bright map ending in a straight cut reads as a
                    // window frame.
                    RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.85), lineWidth: 36)
                        .blur(radius: 22)
                        .allowsHitTesting(false)
                    marks(size: geometry.size)
                }
                // Canvas does not clip to its own bounds, and the street grid is deliberately
                // drawn a diagonal wider than the panel so rotation never exposes a corner.
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
                        .strokeBorder(HudTheme.edge, lineWidth: 1)
                )
            }
        }
    }

    /// The map raster, heading-up: it turns under the marker as the wearer turns, and slides
    /// under it as they walk, so the marker can stay fixed at the centre pointing up.
    ///
    /// The raster is a square `effectiveGroundSpan` metres across, centred where it was fetched,
    /// drawn at the panel's fixed zoom. Between fetches the offset moves it by the distance
    /// walked since.
    private func groundLayer(_ ground: Image, size: CGSize) -> some View {
        let pointsPerMetre = CGFloat(minimap.pointsPerMetre)
        let side = CGFloat(minimap.effectiveGroundSpan) * pointsPerMetre
        return ZStack {
            ground.resizable()
            routeLayer(side: side, pointsPerMetre: pointsPerMetre)
        }
            .frame(width: side, height: side)
            .offset(x: -CGFloat(minimap.groundOffsetEast) * pointsPerMetre,
                    y: CGFloat(minimap.groundOffsetNorth) * pointsPerMetre)
            .animation(.linear(duration: 0.9), value: minimap.groundOffsetEast)
            .animation(.linear(duration: 0.9), value: minimap.groundOffsetNorth)
            // Rotating after the offset turns the map about the panel's centre, which is where
            // the wearer is.
            .rotationEffect(.degrees(-minimap.heading))
            .animation(.easeOut(duration: 0.25), value: minimap.heading)
            .frame(width: size.width, height: size.height)
    }

    /// The route, in the raster's own frame so it turns and slides with the streets under it.
    private func routeLayer(side: CGFloat, pointsPerMetre: CGFloat) -> some View {
        Canvas { context, size in
            guard minimap.route.count > 1 else { return }
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: size.width / 2 + p.x * pointsPerMetre,
                        y: size.height / 2 - p.y * pointsPerMetre)
            }
            var line = Path()
            line.move(to: point(minimap.route[0]))
            for p in minimap.route.dropFirst() { line.addLine(to: point(p)) }
            let style = { (width: CGFloat) in
                StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            }
            context.stroke(line, with: .color(.black.opacity(0.7)), style: style(18))
            context.stroke(line, with: .color(HudTheme.accent), style: style(10))

            let end = point(minimap.route[minimap.route.count - 1])
            context.fill(Path(ellipseIn: CGRect(x: end.x - 16, y: end.y - 16, width: 32, height: 32)),
                         with: .color(.black.opacity(0.7)))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 11, y: end.y - 11, width: 22, height: 22)),
                         with: .color(HudTheme.accent))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)),
                         with: .color(.black))
        }
        .frame(width: side, height: side)
    }

    /// A scale bar length that reads as a round number and stays between about 80 and 220
    /// points, whatever the zoom.
    public static func scaleBar(pointsPerMetre: Double) -> (metres: Int, label: String) {
        let steps = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000]
        let metres = steps.first { Double($0) * pointsPerMetre >= 80 } ?? steps.last!
        return (metres, metres >= 1000 ? "\(metres / 1000) KM" : "\(metres) M")
    }

    /// A deterministic, slightly irregular grid. Alfama is not a grid, which is the point of the
    /// jitter: perfectly straight streets read as a chart rather than a place.
    private func streets(size: CGSize) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.white.opacity(0.04)))

            let rotation = Angle(degrees: -minimap.heading)
            let diagonal = max(size.width, size.height) * 1.6
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            func seeded(_ n: Int) -> CGFloat {
                let x = sin(Double(n) * 12.9898) * 43758.5453
                return CGFloat(x - x.rounded(.down))
            }

            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: rotation)

            // Blocks first, so the streets sit on top of them.
            for i in 0..<14 {
                let bx = (seeded(i * 3) - 0.5) * diagonal * 0.8
                let by = (seeded(i * 3 + 1) - 0.5) * diagonal * 0.8
                let w = 40 + seeded(i * 3 + 2) * 90
                let h = 40 + seeded(i * 7) * 90
                context.fill(Path(CGRect(x: bx, y: by, width: w, height: h)),
                             with: .color(.white.opacity(0.05)))
            }

            for i in -8...8 {
                let jitter = (seeded(i + 100) - 0.5) * 18
                let spacing: CGFloat = 86
                let weight: CGFloat = i % 3 == 0 ? 5 : 2.5
                let alpha: Double = i % 3 == 0 ? 0.26 : 0.14

                var vertical = Path()
                vertical.move(to: CGPoint(x: CGFloat(i) * spacing + jitter, y: -diagonal / 2))
                vertical.addLine(to: CGPoint(x: CGFloat(i) * spacing - jitter, y: diagonal / 2))
                context.stroke(vertical, with: .color(.white.opacity(alpha)), lineWidth: weight)

                let jitter2 = (seeded(i + 200) - 0.5) * 18
                var horizontal = Path()
                horizontal.move(to: CGPoint(x: -diagonal / 2, y: CGFloat(i) * spacing + jitter2))
                horizontal.addLine(to: CGPoint(x: diagonal / 2, y: CGFloat(i) * spacing - jitter2))
                context.stroke(horizontal, with: .color(.white.opacity(alpha)), lineWidth: weight)
            }

        }
    }

    /// The route, in the accent, so it is the only coloured thing on the panel.
    private func route(size: CGSize) -> some View {
        Canvas { context, size in
            context.translateBy(x: size.width / 2, y: size.height / 2)
            var route = Path()
            route.move(to: CGPoint(x: -260, y: 300))
            route.addCurve(to: CGPoint(x: -40, y: 40),
                           control1: CGPoint(x: -200, y: 190),
                           control2: CGPoint(x: -120, y: 120))
            route.addCurve(to: CGPoint(x: 250, y: -230),
                           control1: CGPoint(x: 40, y: -40),
                           control2: CGPoint(x: 150, y: -120))
            context.stroke(route, with: .color(HudTheme.accent),
                           style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
        }
    }

    /// Position, heading, scale and north — the things that stay upright whatever the map does.
    private func marks(size: CGSize) -> some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            // Heading cone, drawn up the screen because the map is rotated under it.
            var cone = Path()
            cone.move(to: centre)
            cone.addLine(to: CGPoint(x: centre.x - 30, y: centre.y - 66))
            cone.addLine(to: CGPoint(x: centre.x + 30, y: centre.y - 66))
            cone.closeSubpath()
            context.fill(cone, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.42), .white.opacity(0.0)]),
                startPoint: centre,
                endPoint: CGPoint(x: centre.x, y: centre.y - 66)))

            context.fill(Path(ellipseIn: CGRect(x: centre.x - 11, y: centre.y - 11,
                                                width: 22, height: 22)),
                         with: .color(.white))
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - 17, y: centre.y - 17,
                                                  width: 34, height: 34)),
                           with: .color(HudTheme.accent), lineWidth: 3)

            // Scale bar: a round distance at the map's zoom. Bottom left on the small panel;
            // beside the north mark in the app, where the trip card has the bottom left.
            let barY = size.height - 30
            let scale = Self.scaleBar(pointsPerMetre: minimap.pointsPerMetre)
            let barLength = CGFloat(Double(scale.metres) * minimap.pointsPerMetre)
            let barX: CGFloat = showsHeader ? 24 : size.width - 104 - barLength
            var bar = Path()
            bar.move(to: CGPoint(x: barX, y: barY))
            bar.addLine(to: CGPoint(x: barX + barLength, y: barY))
            context.stroke(bar, with: .color(.white.opacity(0.65)), lineWidth: 3)
            for x in [barX, barX + barLength] {
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: barY - 6))
                tick.addLine(to: CGPoint(x: x, y: barY + 6))
                context.stroke(tick, with: .color(.white.opacity(0.65)), lineWidth: 3)
            }
            context.draw(Text(scale.label)
                .font(HudTheme.mont(15, .black))
                .foregroundStyle(HudTheme.inkDim),
                at: CGPoint(x: barX + barLength / 2, y: barY - 20))

            // North, bottom right, rotated to the heading.
            let northCentre = CGPoint(x: size.width - 48, y: size.height - 48)
            context.stroke(Path(ellipseIn: CGRect(x: northCentre.x - 24, y: northCentre.y - 24,
                                                  width: 48, height: 48)),
                           with: .color(.white.opacity(0.22)), lineWidth: 2)
            context.drawLayer { layer in
                layer.translateBy(x: northCentre.x, y: northCentre.y)
                layer.rotate(by: Angle(degrees: -minimap.heading))
                var needle = Path()
                needle.move(to: CGPoint(x: 0, y: -19))
                needle.addLine(to: CGPoint(x: -7, y: 3))
                needle.addLine(to: CGPoint(x: 7, y: 3))
                needle.closeSubpath()
                layer.fill(needle, with: .color(.white.opacity(0.85)))
            }
            context.draw(Text(minimap.headingLabel)
                .font(HudTheme.mont(14, .black))
                .foregroundStyle(HudTheme.inkDim),
                at: CGPoint(x: northCentre.x, y: northCentre.y + 34))
        }
    }
}
