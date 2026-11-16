import SwiftUI

/// The sky as it is seen: the horizon low across the glasses in the direction the phone faces,
/// the sky above it to the top, in a stereographic projection (it keeps shapes, so the
/// constellations look like themselves even at the edges).
public struct SkyProjection: Sendable {
    public var facing: Double
    /// The altitude at the middle of the glasses.
    public var centreAlt: Double
    /// Points per unit of the projection's plane.
    public var scale: Double
    public var size: CGSize

    public init(facing: Double, fov: Double, tilt: Double = 0, size: CGSize = HudTheme.glassesSize) {
        self.facing = facing
        self.size = size
        scale = Double(size.width) / 2 / (2 * tan(fov * .pi / 720))
        // Straight ahead, the horizon sits a sixth of the way up: most of the glasses are sky.
        let drop = Double(size.height) * 0.34
        centreAlt = min(2 * atan(drop / (2 * scale)) * 180 / .pi + tilt, 89)
    }

    /// Where on the glasses a point of the sky lands; nil for the far side of the sky.
    public func project(az: Double, alt: Double) -> CGPoint? {
        let d = (az - facing) * .pi / 180, φ = alt * .pi / 180, φ0 = centreAlt * .pi / 180
        let cosc = sin(φ0) * sin(φ) + cos(φ0) * cos(φ) * cos(d)
        guard cosc > -0.6 else { return nil }
        let k = 2 / (1 + cosc)
        let x = k * cos(φ) * sin(d)
        let y = k * (cos(φ0) * sin(φ) - sin(φ0) * cos(φ) * cos(d))
        return CGPoint(x: Double(size.width) / 2 + scale * x, y: Double(size.height) / 2 - scale * y)
    }

    public func project(_ point: HudSnapshot.Sky.Point) -> CGPoint? {
        project(az: Double(point.az), alt: Double(point.alt))
    }

    public func project(_ point: HudSnapshot.Overhead.Point) -> CGPoint? {
        project(az: point.az, alt: point.alt)
    }

    /// The horizon, which this projection always draws as a circle, and whether the ground is
    /// inside it.
    func horizon() -> (centre: CGPoint, radius: CGFloat, groundInside: Bool)? {
        guard let a = project(az: facing - 90, alt: 0), let b = project(az: facing, alt: 0),
              let c = project(az: facing + 90, alt: 0) else { return nil }
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-6 else { return nil }
        let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
        let centre = CGPoint(x: (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
                             y: (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
        let radius = hypot(a.x - centre.x, a.y - centre.y)
        guard let below = project(az: facing, alt: -20) else { return nil }
        return (centre, radius, hypot(below.x - centre.x, below.y - centre.y) < radius)
    }

    func visible(_ p: CGPoint, margin: CGFloat = 40) -> Bool {
        p.x > -margin && p.x < size.width + margin && p.y > -margin && p.y < size.height + margin
    }
}

/// Something in the sky the phone can point out: a plane, the station, a body, a bright star,
/// a sign of the zodiac.
public struct SkyTarget: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case plane = "AIRCRAFT", station = "SPACE STATION", sun = "STAR", moon = "MOON",
             planet = "PLANET", star = "BRIGHT STAR", sign = "ZODIAC"
    }
    public struct Fact: Sendable, Hashable {
        public var label: String
        public var value: String
    }

    public var id: String
    public var kind: Kind
    public var name: String
    public var detail: String
    public var facts: [Fact]
    public var az: Double
    public var alt: Double

    public var isUp: Bool { alt > 0 }

    /// Everything worth pointing out now, nearest and brightest first.
    public static func all(sky: HudSnapshot.Sky, overhead: HudSnapshot.Overhead,
                           layers: Set<SkyLayer>) -> [SkyTarget] {
        var targets: [SkyTarget] = []
        func place(_ az: Double, _ alt: Double) -> Fact {
            Fact(label: "UP", value: "\(Int(alt.rounded()))\u{00B0} \u{00B7} \(SkyModel.compass(az))")
        }
        if layers.contains(.iss), let station = overhead.station {
            targets.append(SkyTarget(
                id: "iss", kind: .station, name: "ISS", detail: "International Space Station",
                facts: [place(station.position.az, station.position.alt),
                        Fact(label: "HEIGHT", value: "\(Int(station.altitude.rounded())) KM"),
                        Fact(label: "SPEED", value: "\(Int(station.speed.rounded()).formatted()) KM/H"),
                        Fact(label: "AWAY", value: "\(Int(station.distance.rounded()).formatted()) KM"),
                        Fact(label: "LIGHT", value: station.sunlit ? "SUNLIT" : "IN SHADOW")],
                az: station.position.az, alt: station.position.alt))
        }
        if layers.contains(.planes) {
            for plane in overhead.planes {
                targets.append(SkyTarget(
                    id: "plane:" + plane.id, kind: .plane, name: plane.callsign,
                    detail: [plane.airline, plane.model].compactMap { $0 }.joined(separator: " \u{00B7} "),
                    facts: [place(plane.position.az, plane.position.alt),
                            Fact(label: "HEIGHT", value: "\(Int(plane.altitude.rounded()).formatted()) M"),
                            Fact(label: "SPEED", value: "\(Int(plane.speed.rounded())) KM/H"),
                            Fact(label: "AWAY", value: "\(Int(plane.distance.rounded())) KM"),
                            Fact(label: "FLYING", value: SkyModel.compass(plane.track))],
                    az: plane.position.az, alt: plane.position.alt))
            }
        }
        for body in sky.bodies.sorted(by: { $0.mag < $1.mag }) {
            var facts = [place(body.az, body.alt)]
            let kind: Kind
            var detail = ""
            switch body.kind {
            case .sun:
                kind = .sun
                detail = "Our star"
                if let sign = sky.sunSign { facts.append(Fact(label: "IN", value: sign.name)) }
                if let set = sky.sunset { facts.append(Fact(label: "SETS", value: set)) }
            case .moon:
                kind = .moon
                detail = sky.moonPhase.capitalized
                facts.append(Fact(label: "LIT", value: "\(sky.moonIllumination)%"))
                if let sign = sky.moonSign { facts.append(Fact(label: "IN", value: sign.name)) }
            case .planet:
                kind = .planet
                detail = "Planet"
                facts.append(Fact(label: "BRIGHTNESS", value: String(format: "%.1f", body.mag)))
            }
            targets.append(SkyTarget(id: "body:" + body.name, kind: kind, name: body.name,
                                     detail: detail, facts: facts, az: body.az, alt: body.alt))
        }
        for star in sky.starNames where star.alt > 8 {
            targets.append(SkyTarget(id: "star:" + star.name, kind: .star, name: star.name.uppercased(),
                                     detail: "Star", facts: [place(Double(star.az), Double(star.alt))],
                                     az: Double(star.az), alt: Double(star.alt)))
        }
        if layers.contains(.zodiac) {
            for sign in sky.signs where sign.alt > 0 {
                var facts = [Fact(label: "SUN IN IT", value: sign.sign.dates),
                             place(Double(sign.az), Double(sign.alt))]
                if sky.sunSign == sign.sign { facts.append(Fact(label: "NOW", value: "THE SUN IS HERE")) }
                if sky.moonSign == sign.sign { facts.append(Fact(label: "NOW", value: "THE MOON IS HERE")) }
                targets.append(SkyTarget(id: "sign:\(sign.sign.rawValue)", kind: .sign,
                                         name: sign.sign.glyph + " " + sign.sign.name,
                                         detail: "Sign of the zodiac", facts: facts,
                                         az: Double(sign.az), alt: Double(sign.alt)))
            }
        }
        return targets
    }
}

/// The sky app, fullscreen on the glasses: the whole canvas is sky. Its controls are on the
/// phone (`SkyControls`): look round, zoom, layers, and what to point out.
public struct SkyApp: View {
    public var sky: HudSnapshot.Sky
    public var overhead: HudSnapshot.Overhead
    public var view: SkyView
    public var heading: Double
    /// The whole canvas held up alone; the centre's size there.
    public var size: CGSize

    public init(_ sky: HudSnapshot.Sky, overhead: HudSnapshot.Overhead = .init(),
                view: SkyView = .init(), heading: Double, size: CGSize = HudTheme.glassesSize) {
        self.sky = sky
        self.overhead = overhead
        self.view = view
        self.heading = heading
        self.size = size
    }

    private var wide: Bool { size.width >= 1400 }

    private var facing: Double {
        ((heading + view.pan).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    private var projection: SkyProjection {
        SkyProjection(facing: facing, fov: view.fov, tilt: view.tilt, size: size)
    }

    private var selected: SkyTarget? {
        guard let id = view.selected else { return nil }
        return SkyTarget.all(sky: sky, overhead: overhead, layers: view.layers).first { $0.id == id }
    }

    public var body: some View {
        let selected = selected
        ZStack(alignment: .topLeading) {
            SkyCanvas(sky: sky, overhead: overhead, layers: view.layers, projection: projection,
                      fov: view.fov, selected: selected)
            // A shade under the words, so star names never run through them.
            RadialGradient(colors: [.black.opacity(0.85), .black.opacity(0)], center: .topLeading,
                           startRadius: 120, endRadius: 640)
                .frame(width: 1100, height: 700)
                .allowsHitTesting(false)
            heading(selected)
                .at(CGRect(x: wide ? 72 : 40, y: wide ? 52 : 36, width: min(900, size.width - 80), height: 240))
            if wide {
                legend
                    .at(CGRect(x: 1000, y: 56, width: 848, height: 40), alignment: .topTrailing)
            }
            if let selected {
                card(selected)
                    .at(CGRect(x: wide ? 72 : 40, y: size.height - 320, width: min(1100, size.width - 80),
                               height: 280), alignment: .bottomLeading)
            }
            if wide {
                footer
                    .at(CGRect(x: 1200, y: 1000, width: 648, height: 40), alignment: .bottomTrailing)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    // MARK: overlay

    private func heading(_ selected: SkyTarget?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(SkyModel.compass(facing)).font(HudTheme.mont(64, .black))
                    .foregroundStyle(HudTheme.ink)
                Text("\(Int(facing.rounded()) % 360)\u{00B0}").font(HudTheme.mont(30, .black))
                    .foregroundStyle(HudTheme.inkDim)
                if view.isAdjusted {
                    Text("\(Int(view.fov.rounded()))\u{00B0} WIDE").font(HudTheme.mont(16, .black))
                        .tracking(2.5).foregroundStyle(HudTheme.inkFaint)
                }
            }
            HStack(spacing: 26) {
                if let set = sky.sunset, sky.sunAltitude > -1 {
                    fact("sunset.fill", "SETS \(set)")
                } else if let rise = sky.sunrise {
                    fact("sunrise.fill", "RISES \(rise)")
                }
                fact(sky.moonSymbol, "\(sky.moonPhase) \u{00B7} \(sky.moonIllumination)%")
            }
            if view.layers.contains(.zodiac), let sun = sky.sunSign, let moon = sky.moonSign {
                HStack(spacing: 26) {
                    sign("SUN IN", sun)
                    sign("MOON IN", moon)
                }
                .foregroundStyle(HudTheme.accent.opacity(0.9))
            }
        }
    }

    private func sign(_ label: String, _ sign: Zodiac) -> some View {
        HStack(spacing: 8) {
            Text(label).font(HudTheme.mont(17, .black)).tracking(2.5)
            Text(sign.glyph).font(.system(size: 24, weight: .regular))
            Text(sign.name).font(HudTheme.mont(17, .black)).tracking(2.5)
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            Text(text).font(HudTheme.mont(17, .black)).tracking(2.5)
        }
        .foregroundStyle(HudTheme.inkDim)
    }

    /// Which layers are on, quietly: they are switched on the phone.
    private var legend: some View {
        HStack(spacing: 18) {
            ForEach(SkyLayer.allCases, id: \.self) { layer in
                let on = view.layers.contains(layer)
                HStack(spacing: 7) {
                    Circle().fill(on ? HudTheme.accent : Color.clear)
                        .overlay(Circle().strokeBorder(on ? Color.clear : HudTheme.inkFaint, lineWidth: 1.5))
                        .frame(width: 8, height: 8)
                    Text(layer.title).font(HudTheme.mont(13, .black)).tracking(2.5)
                        .foregroundStyle(on ? HudTheme.inkDim : HudTheme.inkFaint)
                }
            }
        }
        .padding(.horizontal, 20).frame(height: 40)
        .background(Color.black.opacity(0.92), in: Capsule())
    }

    private func card(_ target: SkyTarget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(target.isUp ? target.kind.rawValue : target.kind.rawValue + " \u{00B7} BELOW THE HORIZON")
                .font(HudTheme.mont(15, .black)).tracking(3)
                .foregroundStyle(HudTheme.accent)
            Text(target.name).font(HudTheme.mont(52, .black)).foregroundStyle(HudTheme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !target.detail.isEmpty {
                Text(target.detail).font(HudTheme.mont(22, .semibold)).foregroundStyle(HudTheme.inkDim)
            }
            HStack(alignment: .top, spacing: 34) {
                ForEach(target.facts, id: \.self) { fact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fact.label).font(HudTheme.mont(12, .black)).tracking(2.5)
                            .foregroundStyle(HudTheme.inkFaint)
                        Text(fact.value).font(HudTheme.mont(22, .black)).foregroundStyle(HudTheme.ink)
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 30).padding(.vertical, 24)
        .background(Color.black.opacity(0.93), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(HudTheme.edge, lineWidth: 1.5))
    }

    private var footer: some View {
        HStack(spacing: 20) {
            if view.layers.contains(.planes), !overhead.status.isEmpty {
                Text(overhead.status).foregroundStyle(HudTheme.inkDim)
            }
            if view.layers.contains(.planes) { Text("AIRCRAFT \u{00B7} ADSB.LOL") }
            if view.layers.contains(.iss), overhead.station != nil { Text("ISS \u{00B7} WHERETHEISS.AT") }
        }
        .font(HudTheme.mont(11, .black)).tracking(2.5)
        .foregroundStyle(HudTheme.inkFaint)
    }
}

/// The drawing itself, every layer in one canvas.
struct SkyCanvas: View {
    var sky: HudSnapshot.Sky
    var overhead: HudSnapshot.Overhead
    var layers: Set<SkyLayer>
    var projection: SkyProjection
    var fov: Double
    var selected: SkyTarget?

    static let station = Color(red: 0.55, green: 0.86, blue: 1.0)

    var body: some View {
        Canvas { context, size in
            let pr = projection
            // In daylight the stars are there but faint; at night, full.
            let night = sky.sunAltitude < -6
            let starLight = night ? 1.0 : (sky.sunAltitude < 0 ? 0.6 : 0.35)
            let zoom = CGFloat(min(max((110 / fov).squareRoot(), 0.8), 1.9))

            if layers.contains(.milkyWay) { milkyWay(&context, pr, light: starLight) }
            if layers.contains(.grid) { grid(&context, pr) }
            if layers.contains(.zodiac) { ecliptic(&context, pr) }
            if layers.contains(.figures) { figures(&context, pr, light: starLight) }
            stars(&context, pr, light: starLight, zoom: zoom)
            if layers.contains(.names) { names(&context, pr, light: starLight) }
            if layers.contains(.zodiac) { signs(&context, pr) }
            bodies(&context, pr, zoom: zoom)
            if layers.contains(.iss), let station = overhead.station { self.station(&context, pr, station) }
            if layers.contains(.planes) { planes(&context, pr) }
            ground(&context, pr, size: size)
            if let selected { mark(&context, pr, selected) }
        }
        .frame(width: projection.size.width, height: projection.size.height)
    }

    /// A line through sky points, lifted where it jumps (round the back of the sky).
    private func path(_ points: [CGPoint?], closed: Bool = false, jump: CGFloat = 900) -> Path {
        var path = Path()
        var last: CGPoint?
        for point in points {
            guard let point else { last = nil; continue }
            if let last, hypot(point.x - last.x, point.y - last.y) < jump {
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
            last = point
        }
        if closed { path.closeSubpath() }
        return path
    }

    private func dot(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    private func glow(_ context: inout GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ colour: Color,
                      _ strength: Double) {
        context.fill(dot(p, r), with: .radialGradient(
            Gradient(colors: [colour.opacity(strength), colour.opacity(0)]),
            center: p, startRadius: 0, endRadius: r))
    }

    // MARK: layers

    /// Soft light where the galaxy is, brighter where more of its outline levels overlap:
    /// overlapping dots blurred into one glow.
    private func milkyWay(_ context: inout GraphicsContext, _ pr: SkyProjection, light: Double) {
        let radius = pr.scale * 1.25 * .pi / 180
        let strength: [Double] = [0.07, 0.1, 0.13, 0.17, 0.22]
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: radius * 0.8))
            let tint = Color(red: 0.8, green: 0.86, blue: 1.0)
            for band in sky.milkyWay {
                var path = Path()
                for point in band.points {
                    guard let p = pr.project(point), pr.visible(p, margin: radius * 2) else { continue }
                    path.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                }
                let level = min(max(band.level, 1), strength.count) - 1
                layer.fill(path, with: .color(tint.opacity(strength[level] * light)))
            }
        }
    }

    private func grid(_ context: inout GraphicsContext, _ pr: SkyProjection) {
        let style = StrokeStyle(lineWidth: 1, dash: [3, 7])
        for altitude in stride(from: 15.0, through: 75, by: 15) {
            let ring = stride(from: 0.0, through: 360, by: 3).map { pr.project(az: $0, alt: altitude) }
            context.stroke(path(ring), with: .color(.white.opacity(0.09)), style: style)
            if let p = pr.project(az: pr.facing + 4, alt: altitude), pr.visible(p) {
                context.draw(Text("\(Int(altitude))\u{00B0}").font(HudTheme.mont(12, .black))
                    .foregroundColor(.white.opacity(0.25)), at: p, anchor: .bottomLeading)
            }
        }
        for azimuth in stride(from: 0.0, to: 360, by: 30) {
            let line = stride(from: 0.0, through: 80, by: 4).map { pr.project(az: azimuth, alt: $0) }
            context.stroke(path(line), with: .color(.white.opacity(0.06)), style: style)
        }
    }

    private func ecliptic(_ context: inout GraphicsContext, _ pr: SkyProjection) {
        let points = sky.ecliptic.map { pr.project($0) }
        context.stroke(path(points), with: .color(HudTheme.accent.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1.6, dash: [10, 9]))
        // Where one sign ends and the next begins: a short bar across the line.
        for index in stride(from: 0, to: sky.ecliptic.count - 1, by: 15) {
            guard let p = points[index], let q = points[index + 1], pr.visible(p) else { continue }
            let angle = atan2(q.y - p.y, q.x - p.x) + .pi / 2
            var bar = Path()
            bar.move(to: CGPoint(x: p.x - cos(angle) * 11, y: p.y - sin(angle) * 11))
            bar.addLine(to: CGPoint(x: p.x + cos(angle) * 11, y: p.y + sin(angle) * 11))
            context.stroke(bar, with: .color(HudTheme.accent.opacity(0.7)), lineWidth: 2)
        }
    }

    private func signs(_ context: inout GraphicsContext, _ pr: SkyProjection) {
        for sign in sky.signs where sign.alt > -3 {
            guard let p = pr.project(az: Double(sign.az), alt: Double(sign.alt)), pr.visible(p) else { continue }
            let now = sign.sign == sky.sunSign
            if now { glow(&context, p, 46, HudTheme.accent, 0.3) }
            context.draw(Text(sign.sign.glyph).font(.system(size: 34, weight: .light))
                .foregroundColor(HudTheme.accent.opacity(now ? 1 : 0.85)), at: p)
            context.draw(Text(sign.sign.name).font(HudTheme.mont(12, .black)).tracking(3)
                .foregroundColor(HudTheme.accent.opacity(0.7)),
                         at: CGPoint(x: p.x, y: p.y + 48))
        }
    }

    private func figures(_ context: inout GraphicsContext, _ pr: SkyProjection, light: Double) {
        let zodiac = layers.contains(.zodiac)
        for figure in sky.lines {
            let line = path(figure.points.map { pr.project($0) }, jump: 400)
            if zodiac && figure.zodiac {
                context.stroke(line, with: .color(HudTheme.accent.opacity(0.45 * light)), lineWidth: 1.6)
            } else {
                context.stroke(line, with: .color(.white.opacity(0.2 * light)), lineWidth: 1.2)
            }
        }
    }

    private func stars(_ context: inout GraphicsContext, _ pr: SkyProjection, light: Double, zoom: CGFloat) {
        for star in sky.stars {
            guard let p = pr.project(az: Double(star.az), alt: Double(star.alt)), pr.visible(p, margin: 10)
            else { continue }
            let r = CGFloat(min(max(4.6 - 0.8 * Double(star.mag), 0.8), 6.5)) * zoom
            let colour = SkyCanvas.colour(bv: star.bv)
            if star.mag < 1.8 { glow(&context, p, r * 4.5, colour, 0.28 * light) }
            context.fill(dot(p, r), with: .color(colour.opacity(min(1, 0.45 + light * 0.55))))
        }
    }

    private func names(_ context: inout GraphicsContext, _ pr: SkyProjection, light: Double) {
        let zodiac = layers.contains(.zodiac)
        for label in sky.constellations {
            guard let p = pr.project(az: Double(label.az), alt: Double(label.alt)), pr.visible(p) else { continue }
            let gold = zodiac && label.zodiac
            context.draw(Text(label.name).font(HudTheme.mont(13, .black)).tracking(3.5)
                .foregroundColor((gold ? HudTheme.accent : .white).opacity((gold ? 0.6 : 0.3) * light)), at: p)
        }
        for label in sky.starNames {
            guard let p = pr.project(az: Double(label.az), alt: Double(label.alt)), pr.visible(p) else { continue }
            context.draw(Text(label.name).font(HudTheme.mont(15, .semibold))
                .foregroundColor(.white.opacity(0.62 * light)),
                         at: CGPoint(x: p.x + 12, y: p.y - 12), anchor: .leading)
        }
    }

    private func bodies(_ context: inout GraphicsContext, _ pr: SkyProjection, zoom: CGFloat) {
        for body in sky.bodies {
            guard let p = pr.project(az: body.az, alt: body.alt), pr.visible(p, margin: 80) else { continue }
            switch body.kind {
            case .sun:
                glow(&context, p, 90 * zoom, HudTheme.accent, 0.4)
                context.fill(dot(p, 20 * zoom), with: .color(HudTheme.accent))
                label(&context, "SUN", at: p, offset: 30 * zoom, colour: HudTheme.accent)
            case .moon:
                glow(&context, p, 70 * zoom, .white, 0.16)
                var moon = context.resolve(Image(systemName: sky.moonSymbol))
                moon.shading = .color(.white)
                let side = 44 * zoom
                context.draw(moon, in: CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side))
                label(&context, "MOON", at: p, offset: side / 2 + 10, colour: .white.opacity(0.85))
            case .planet:
                let colour = SkyCanvas.planet(body.name)
                let r = CGFloat(min(max(5 - 0.7 * body.mag, 4), 8)) * zoom
                glow(&context, p, r * 4, colour, 0.35)
                context.fill(dot(p, r), with: .color(colour))
                if body.name == "SATURN" {
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: p.x - r * 2.1, y: p.y - r * 0.7, width: r * 4.2, height: r * 1.4))
                    context.stroke(ring, with: .color(colour.opacity(0.8)), lineWidth: 1.4)
                }
                label(&context, body.name, at: p, offset: r + 10, colour: colour)
            }
        }
    }

    private func label(_ context: inout GraphicsContext, _ text: String, at p: CGPoint, offset: CGFloat,
                       colour: Color) {
        context.draw(Text(text).font(HudTheme.mont(16, .black)).tracking(3).foregroundColor(colour),
                     at: CGPoint(x: p.x + offset, y: p.y), anchor: .leading)
    }

    private func station(_ context: inout GraphicsContext, _ pr: SkyProjection,
                         _ station: HudSnapshot.Overhead.Station) {
        let colour = SkyCanvas.station
        context.stroke(path(station.path.map { pr.project($0) }), with: .color(colour.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 10]))
        guard let p = pr.project(station.position), pr.visible(p) else { return }
        glow(&context, p, 34, colour, station.sunlit ? 0.45 : 0.15)
        // A body and its two wings of panels.
        context.fill(Path(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(colour))
        var wings = Path()
        wings.addRect(CGRect(x: p.x - 20, y: p.y - 6, width: 11, height: 12))
        wings.addRect(CGRect(x: p.x + 9, y: p.y - 6, width: 11, height: 12))
        context.stroke(wings, with: .color(colour), lineWidth: 1.6)
        context.draw(Text("ISS").font(HudTheme.mont(18, .black)).tracking(3).foregroundColor(colour),
                     at: CGPoint(x: p.x + 30, y: p.y - 9), anchor: .leading)
        context.draw(Text("\(Int(station.altitude.rounded())) KM UP").font(HudTheme.mont(12, .black))
            .tracking(2).foregroundColor(colour.opacity(0.7)),
                     at: CGPoint(x: p.x + 30, y: p.y + 11), anchor: .leading)
    }

    private func planes(_ context: inout GraphicsContext, _ pr: SkyProjection) {
        var plane = context.resolve(Image(systemName: "airplane"))
        plane.shading = .color(.white)
        // Far ones first, so near ones draw over them.
        for flight in overhead.planes.reversed() {
            guard let p = pr.project(flight.position), pr.visible(p) else { continue }
            let near = CGFloat(min(max(1.4 - flight.distance / 80, 0.7), 1.4))
            context.stroke(path(flight.trail.map { pr.project($0) } + [p]),
                           with: .color(.white.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var angle: CGFloat = 0
            if let ahead = pr.project(flight.ahead), hypot(ahead.x - p.x, ahead.y - p.y) > 0.5 {
                angle = atan2(ahead.y - p.y, ahead.x - p.x)
            }
            var turned = context
            turned.translateBy(x: p.x, y: p.y)
            turned.rotate(by: .radians(angle))
            let side = 26 * near
            turned.draw(plane, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
            context.draw(Text(flight.callsign).font(HudTheme.mont(15 * near, .black)).foregroundColor(.white),
                         at: CGPoint(x: p.x + side * 0.7, y: p.y - 9), anchor: .leading)
            let height = flight.altitude >= 1000
                ? String(format: "%.1f KM", flight.altitude / 1000) : "\(Int(flight.altitude)) M"
            let line = [flight.model, height].compactMap { $0 }.joined(separator: " \u{00B7} ")
            context.draw(Text(line).font(HudTheme.mont(11 * near, .black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.5)),
                         at: CGPoint(x: p.x + side * 0.7, y: p.y + 9), anchor: .leading)
        }
    }

    /// Below the horizon is the ground: blacked out (clear, on the glasses), with a faint haze
    /// along its edge, a line, and the compass along it.
    private func ground(_ context: inout GraphicsContext, _ pr: SkyProjection, size: CGSize) {
        guard let horizon = pr.horizon() else { return }
        let c = horizon.centre, r = horizon.radius
        let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let haze = Gradient(colors: [.white.opacity(0.08), .white.opacity(0)])
        if horizon.groundInside {
            context.fill(circle, with: .color(.black))
            context.fill(circle, with: .radialGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.08)]),
                center: c, startRadius: max(r - 170, 0), endRadius: r))
        } else {
            var earth = Path(CGRect(x: -2000, y: -2000, width: size.width + 4000, height: size.height + 4000))
            earth.addPath(circle)
            context.fill(earth, with: .color(.black), style: FillStyle(eoFill: true))
            context.fill(earth, with: .radialGradient(haze, center: c, startRadius: r, endRadius: r + 170),
                         style: FillStyle(eoFill: true))
        }
        context.stroke(circle, with: .color(.white.opacity(0.4)), lineWidth: 1.6)

        for azimuth in stride(from: 0, to: 360, by: 5) {
            guard let p = pr.project(az: Double(azimuth), alt: 0), pr.visible(p) else { continue }
            let major = azimuth % 45 == 0, mid = azimuth % 15 == 0
            // Ticks and names hang into the ground, square to the horizon.
            var out = CGVector(dx: p.x - c.x, dy: p.y - c.y)
            let length = max(hypot(out.dx, out.dy), 0.001)
            out = CGVector(dx: out.dx / length, dy: out.dy / length)
            if horizon.groundInside { out = CGVector(dx: -out.dx, dy: -out.dy) }
            let reach: CGFloat = major ? 18 : mid ? 11 : 6
            var tick = Path()
            tick.move(to: p)
            tick.addLine(to: CGPoint(x: p.x + out.dx * reach, y: p.y + out.dy * reach))
            context.stroke(tick, with: .color(.white.opacity(major ? 0.7 : 0.35)), lineWidth: major ? 2 : 1.2)
            if major {
                let name = SkyModel.compass(Double(azimuth))
                context.draw(Text(name).font(HudTheme.mont(name.count == 1 ? 30 : 20, .black))
                    .foregroundColor(name == "N" ? HudTheme.accent : .white.opacity(0.8)),
                             at: CGPoint(x: p.x + out.dx * 42, y: p.y + out.dy * 42))
            } else if mid {
                context.draw(Text("\(azimuth)").font(HudTheme.mont(12, .black))
                    .foregroundColor(.white.opacity(0.35)),
                             at: CGPoint(x: p.x + out.dx * 26, y: p.y + out.dy * 26))
            }
        }
    }

    /// Brackets round what the phone picked, or an arrow at the edge towards it.
    private func mark(_ context: inout GraphicsContext, _ pr: SkyProjection, _ target: SkyTarget) {
        guard let p = pr.project(az: target.az, alt: target.alt) else { return }
        let size = pr.size
        if pr.visible(p, margin: -30) {
            let r: CGFloat = 34, arm: CGFloat = 12
            var brackets = Path()
            for (sx, sy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
                let corner = CGPoint(x: p.x + r * sx, y: p.y + r * sy)
                brackets.move(to: CGPoint(x: corner.x, y: corner.y - arm * sy))
                brackets.addLine(to: corner)
                brackets.addLine(to: CGPoint(x: corner.x - arm * sx, y: corner.y))
            }
            context.stroke(brackets, with: .color(HudTheme.accent), lineWidth: 3)
        } else {
            // Off the glasses: a chevron at the edge, pointing the way to turn.
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let angle = atan2(p.y - centre.y, p.x - centre.x)
            let edge = CGPoint(x: min(max(centre.x + cos(angle) * 2000, 70), size.width - 70),
                               y: min(max(centre.y + sin(angle) * 2000, 120), size.height - 120))
            var chevron = Path()
            chevron.move(to: CGPoint(x: -14, y: -20))
            chevron.addLine(to: CGPoint(x: 10, y: 0))
            chevron.addLine(to: CGPoint(x: -14, y: 20))
            var turned = context
            turned.translateBy(x: edge.x, y: edge.y)
            turned.rotate(by: .radians(angle))
            turned.stroke(chevron, with: .color(HudTheme.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
    }

    /// A star's tint from its colour index: blue-white to orange, kept pale.
    static func colour(bv: Float) -> Color {
        let t = Double(min(max((bv + 0.3) / 2.0, 0), 1))
        return Color(red: 0.78 + 0.22 * t, green: 0.86 - 0.06 * t, blue: 1.0 - 0.4 * t)
    }

    static func planet(_ name: String) -> Color {
        switch name {
        case "MARS": return Color(red: 1.0, green: 0.55, blue: 0.42)
        case "JUPITER": return Color(red: 1.0, green: 0.88, blue: 0.7)
        case "SATURN": return Color(red: 0.95, green: 0.8, blue: 0.5)
        case "VENUS": return Color(red: 1.0, green: 1.0, blue: 0.9)
        default: return Color(white: 0.85)
        }
    }
}
