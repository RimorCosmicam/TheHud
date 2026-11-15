import Foundation
import CAstronomy

/// Works out the sky over a place at a moment: the sun's day and the moon's phase for the
/// widget, and every star, figure and planet above the horizon for the fullscreen chart.
///
/// The positions come from Astronomy Engine (sun, moon, planets, and the conversion of the
/// catalogue's fixed star positions to the local sky); the stars and constellation figures
/// from d3-celestial's catalogue. Nothing here is our own astronomy.
public enum SkyModel {
    public static func compute(at date: Date, latitude: Double, longitude: Double,
                               timeZone: TimeZone = .current,
                               locale: Locale = .current) -> HudSnapshot.Sky {
        var sky = HudSnapshot.Sky()
        sky.hasLocation = true
        let observer = Astronomy_MakeObserver(latitude, longitude, 0)
        var time = astroTime(date)

        let clock = DateFormatter()
        clock.locale = locale
        clock.timeZone = timeZone
        clock.setLocalizedDateFormatFromTemplate("jmm")
        func text(_ result: astro_search_result_t) -> String? {
            result.status == ASTRO_SUCCESS ? clock.string(from: self.date(result.time)) : nil
        }

        // The day: searched from local midnight, so it is today's sunrise even after it.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = astroTime(calendar.startOfDay(for: date))
        let rise = Astronomy_SearchRiseSetEx(BODY_SUN, observer, DIRECTION_RISE, midnight, 1, 0)
        let set = Astronomy_SearchRiseSetEx(BODY_SUN, observer, DIRECTION_SET, midnight, 1, 0)
        let golden = Astronomy_SearchAltitude(BODY_SUN, observer, DIRECTION_SET, midnight, 1, 6)
        sky.sunrise = text(rise)
        sky.sunset = text(set)
        sky.goldenHour = text(golden)
        if rise.status == ASTRO_SUCCESS, set.status == ASTRO_SUCCESS {
            let progress = (time.ut - rise.time.ut) / (set.time.ut - rise.time.ut)
            sky.dayProgress = (0...1).contains(progress) ? progress : nil
        }

        let phase = Astronomy_MoonPhase(time)
        if phase.status == ASTRO_SUCCESS {
            let named = moonPhase(phase.angle)
            sky.moonPhase = named.name
            sky.moonSymbol = named.symbol
        }
        let illumination = Astronomy_Illumination(BODY_MOON, time)
        if illumination.status == ASTRO_SUCCESS {
            sky.moonIllumination = Int((illumination.phase_fraction * 100).rounded())
        }
        sky.moonrise = text(Astronomy_SearchRiseSetEx(BODY_MOON, observer, DIRECTION_RISE, time, 1, 0))
        sky.moonset = text(Astronomy_SearchRiseSetEx(BODY_MOON, observer, DIRECTION_SET, time, 1, 0))

        // The sun, the moon and the five planets you can see.
        let bodies: [(astro_body_t, String, HudSnapshot.Sky.Body.Kind)] = [
            (BODY_SUN, "SUN", .sun), (BODY_MOON, "MOON", .moon),
            (BODY_MERCURY, "MERCURY", .planet), (BODY_VENUS, "VENUS", .planet),
            (BODY_MARS, "MARS", .planet), (BODY_JUPITER, "JUPITER", .planet),
            (BODY_SATURN, "SATURN", .planet),
        ]
        for (body, name, kind) in bodies {
            let equator = Astronomy_Equator(body, &time, observer, EQUATOR_OF_DATE, ABERRATION)
            guard equator.status == ASTRO_SUCCESS else { continue }
            let horizon = Astronomy_Horizon(&time, observer, equator.ra, equator.dec,
                                            REFRACTION_NORMAL)
            let magnitude = Astronomy_Illumination(body, time)
            if kind == .sun { sky.sunAltitude = horizon.altitude }
            sky.bodies.append(.init(kind: kind, name: name, az: horizon.azimuth,
                                    alt: horizon.altitude,
                                    mag: magnitude.status == ASTRO_SUCCESS ? magnitude.mag : 0))
        }

        // The catalogue's positions are for the year 2000; the drift since is a few tenths of
        // a degree, far below what a chart this size shows.
        guard let catalogue = SkyCatalogue.shared else { return sky }
        func local(_ ra: Float, _ dec: Float) -> (az: Float, alt: Float) {
            let h = Astronomy_Horizon(&time, observer, Double(ra) / 15, Double(dec), REFRACTION_NORMAL)
            return (Float(h.azimuth), Float(h.altitude))
        }
        sky.stars.reserveCapacity(catalogue.stars.count / 2)
        for star in catalogue.stars {
            let p = local(star.ra, star.dec)
            if p.alt > -1 {
                sky.stars.append(.init(az: p.az, alt: p.alt, mag: star.mag, bv: star.bv))
            }
        }
        sky.lines = catalogue.lines.compactMap { line in
            let points = line.points.map { local($0.ra, $0.dec) }
                .map { HudSnapshot.Sky.Point(az: $0.az, alt: $0.alt) }
            guard points.contains(where: { $0.alt > 0 }) else { return nil }
            return .init(points: points, zodiac: Zodiac.constellations.contains(line.id))
        }
        sky.constellations = catalogue.constellations.compactMap { label in
            let p = local(label.ra, label.dec)
            return p.alt > 2 ? .init(az: p.az, alt: p.alt, name: label.name,
                                     zodiac: Zodiac.constellations.contains(label.id)) : nil
        }
        // Dots, a level each: only the ones above the ground are kept.
        sky.milkyWay = catalogue.milkyWay.compactMap { band in
            let points = band.points.map { local($0.ra, $0.dec) }
                .filter { $0.alt > -3 }
                .map { HudSnapshot.Sky.Point(az: $0.az, alt: $0.alt) }
            return points.isEmpty ? nil : .init(level: band.level, points: points)
        }

        // The ecliptic, from ecliptic longitude straight to the sky: on it the latitude is
        // nought, so right ascension and declination follow from the tilt alone.
        let tilt = 23.4393 * Double.pi / 180
        func onEcliptic(_ longitude: Double) -> (az: Float, alt: Float) {
            let l = longitude * .pi / 180
            let ra = atan2(sin(l) * cos(tilt), cos(l)) * 180 / .pi
            let dec = asin(sin(tilt) * sin(l)) * 180 / .pi
            return local(Float((ra + 360).truncatingRemainder(dividingBy: 360)), Float(dec))
        }
        sky.ecliptic = stride(from: 0.0, through: 360, by: 2).map {
            let p = onEcliptic($0)
            return .init(az: p.az, alt: p.alt)
        }
        sky.signs = Zodiac.allCases.map { sign in
            let p = onEcliptic(Double(sign.rawValue) * 30 + 15)
            return .init(sign: sign, az: p.az, alt: p.alt)
        }
        let sun = Astronomy_SunPosition(time)
        if sun.status == ASTRO_SUCCESS { sky.sunSign = Zodiac(longitude: sun.elon) }
        let moon = Astronomy_EclipticGeoMoon(time)
        if moon.status == ASTRO_SUCCESS { sky.moonSign = Zodiac(longitude: moon.lon) }
        sky.starNames = catalogue.names.compactMap { label in
            let p = local(label.ra, label.dec)
            return p.alt > 2 ? .init(az: p.az, alt: p.alt, name: label.name) : nil
        }
        return sky
    }

    /// The eight phases by the moon's angle from the sun, each a quarter's half wide.
    public static func moonPhase(_ angle: Double) -> (name: String, symbol: String) {
        let phases = [("NEW MOON", "new.moon"), ("WAXING CRESCENT", "waxing.crescent"),
                      ("FIRST QUARTER", "first.quarter"), ("WAXING GIBBOUS", "waxing.gibbous"),
                      ("FULL MOON", "full.moon"), ("WANING GIBBOUS", "waning.gibbous"),
                      ("LAST QUARTER", "last.quarter"), ("WANING CRESCENT", "waning.crescent")]
        let index = Int(((angle.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8
        return (phases[index].0, "moonphase." + phases[index].1)
    }

    /// Astronomy Engine counts days from noon UTC on 1 January 2000.
    static func astroTime(_ date: Date) -> astro_time_t {
        Astronomy_TimeFromDays((date.timeIntervalSince1970 - 946_728_000) / 86_400)
    }

    static func date(_ time: astro_time_t) -> Date {
        Date(timeIntervalSince1970: time.ut * 86_400 + 946_728_000)
    }

    /// Compass point for an azimuth: "N", "NE", ...
    public static func compass(_ azimuth: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int(((azimuth.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8]
    }
}

/// The twelve signs of the (tropical) zodiac, thirty degrees of ecliptic longitude each from
/// the March equinox: how horoscopes count, not where the constellations now sit.
public enum Zodiac: Int, CaseIterable, Sendable {
    case aries, taurus, gemini, cancer, leo, virgo, libra, scorpio, sagittarius, capricorn,
         aquarius, pisces

    public init(longitude: Double) {
        let degrees = (longitude.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        self = Zodiac(rawValue: Int(degrees / 30)) ?? .aries
    }

    public var name: String {
        ["ARIES", "TAURUS", "GEMINI", "CANCER", "LEO", "VIRGO", "LIBRA", "SCORPIO",
         "SAGITTARIUS", "CAPRICORN", "AQUARIUS", "PISCES"][rawValue]
    }

    /// The sign's glyph, asked for as text rather than emoji.
    public var glyph: String {
        let scalar = Unicode.Scalar(0x2648 + UInt32(rawValue))!
        return String(Character(scalar)) + "\u{FE0E}"
    }

    /// When the sun is in it, give or take a day by year.
    public var dates: String {
        ["MAR 21 \u{2013} APR 19", "APR 20 \u{2013} MAY 20", "MAY 21 \u{2013} JUN 20",
         "JUN 21 \u{2013} JUL 22", "JUL 23 \u{2013} AUG 22", "AUG 23 \u{2013} SEP 22",
         "SEP 23 \u{2013} OCT 22", "OCT 23 \u{2013} NOV 21", "NOV 22 \u{2013} DEC 21",
         "DEC 22 \u{2013} JAN 19", "JAN 20 \u{2013} FEB 18", "FEB 19 \u{2013} MAR 20"][rawValue]
    }

    /// d3-celestial's ids for the constellations the signs are named after.
    static let constellations: Set<String> = ["Ari", "Tau", "Gem", "Cnc", "Leo", "Vir", "Lib",
                                              "Sco", "Sgr", "Cap", "Aqr", "Psc"]
}

/// What the sky app draws over the stars, each switched from its row of chips.
public enum SkyLayer: String, CaseIterable, Codable, Sendable {
    case figures, names, zodiac, milkyWay, planes, iss, grid

    public var title: String {
        switch self {
        case .figures: return "FIGURES"
        case .names: return "NAMES"
        case .zodiac: return "ZODIAC"
        case .milkyWay: return "MILKY WAY"
        case .planes: return "PLANES"
        case .iss: return "ISS"
        case .grid: return "GRID"
        }
    }

    public static let standard: Set<SkyLayer> = [.figures, .names, .zodiac, .milkyWay, .planes, .iss]
}

/// The sky app's settings: what it shows, and how wide a piece of sky fills the glasses.
public struct SkyView: Sendable, Equatable {
    public var layers: Set<SkyLayer>
    /// Degrees of sky across the glasses.
    public var fov: Double
    /// Degrees turned from where the phone faces: looking round without turning round.
    public var pan: Double = 0
    /// Degrees looked up from the usual view, which keeps the horizon near the bottom.
    public var tilt: Double = 0
    /// The thing picked on the phone to be pointed out: see `SkyTarget`.
    public var selected: String?

    public static let fovRange = 40.0...170.0
    public static let standardFOV = 110.0

    public init(layers: Set<SkyLayer> = SkyLayer.standard, fov: Double = SkyView.standardFOV) {
        self.layers = layers
        self.fov = fov
    }

    public var isAdjusted: Bool { pan != 0 || tilt != 0 || fov != Self.standardFOV }

    public mutating func recentre() {
        pan = 0
        tilt = 0
        fov = Self.standardFOV
    }

    public static let tiltRange = 0.0...70.0

    /// One notch of the wheel: down for more sky, up for closer.
    public mutating func zoom(notches: Int) {
        zoom(by: pow(1.08, Double(notches)))
    }

    /// Under 1 shows less sky, closer.
    public mutating func zoom(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        fov = min(max(fov * factor, Self.fovRange.lowerBound), Self.fovRange.upperBound)
    }

    /// Looks round and up by some degrees. Pan wraps; tilt stops at the horizon and short of
    /// the top, where the projection runs out of sky above.
    public mutating func look(pan dPan: Double, tilt dTilt: Double) {
        pan = ((pan + dPan + 180).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) - 180
        tilt = min(max(tilt + dTilt, Self.tiltRange.lowerBound), Self.tiltRange.upperBound)
    }

    public mutating func toggle(_ layer: SkyLayer) {
        if layers.contains(layer) { layers.remove(layer) } else { layers.insert(layer) }
    }
}

/// The star catalogue, read once from the bundle: stars to magnitude 5.5, the constellation
/// figures, names for the brightest, and the Milky Way.
final class SkyCatalogue: @unchecked Sendable {
    struct Star { var ra: Float; var dec: Float; var mag: Float; var bv: Float }
    struct Point { var ra: Float; var dec: Float }
    struct Label { var ra: Float; var dec: Float; var name: String; var id: String = "" }
    struct Line { var id: String; var points: [Point] }
    struct Band { var level: Int; var points: [Point] }

    let stars: [Star]
    let lines: [Line]
    let constellations: [Label]
    let names: [Label]
    let milkyWay: [Band]

    static let shared: SkyCatalogue? = {
        guard let url = Bundle.module.url(forResource: "sky", withExtension: "json",
                                          subdirectory: "Sky"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? SkyCatalogue(json: data)
    }()

    init(json: Data) throws {
        struct Raw: Decodable {
            struct Figure: Decodable { var c: String; var p: [[Float]] }
            var stars: [[Float]]
            var lines: [Figure]
            var labels: [[Label3]]
            var names: [[Label3]]
            var milkyWay: [[Label3OrPoints]]
        }
        // A Milky Way row is its level, then its ring.
        enum Label3OrPoints: Decodable {
            case level(Int), ring([[Float]])
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let n = try? c.decode(Int.self) { self = .level(n) } else {
                    self = .ring(try c.decode([[Float]].self))
                }
            }
        }
        // Rows mix numbers and a name, so each cell decodes as either.
        enum Label3: Decodable {
            case number(Float), text(String)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let n = try? c.decode(Float.self) { self = .number(n) } else {
                    self = .text(try c.decode(String.self))
                }
            }
            var number: Float { if case let .number(n) = self { return n }; return 0 }
            var text: String { if case let .text(t) = self { return t }; return "" }
        }
        let raw = try JSONDecoder().decode(Raw.self, from: json)
        stars = raw.stars.compactMap { $0.count >= 4 ? Star(ra: $0[0], dec: $0[1], mag: $0[2], bv: $0[3]) : nil }
        func points(_ rows: [[Float]]) -> [Point] {
            rows.compactMap { $0.count >= 2 ? Point(ra: $0[0], dec: $0[1]) : nil }
        }
        lines = raw.lines.map { Line(id: $0.c, points: points($0.p)) }
        func label(_ row: [Label3]) -> Label? {
            row.count >= 3 ? Label(ra: row[0].number, dec: row[1].number, name: row[2].text,
                                   id: row.count > 3 ? row[3].text : "") : nil
        }
        constellations = raw.labels.compactMap(label)
        names = raw.names.compactMap(label)
        milkyWay = raw.milkyWay.compactMap { row in
            guard row.count == 2, case let .level(level) = row[0], case let .ring(ring) = row[1] else {
                return nil
            }
            return Band(level: level, points: points(ring))
        }
    }
}
