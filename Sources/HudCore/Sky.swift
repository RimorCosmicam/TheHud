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
            let points = line.map { local($0.ra, $0.dec) }.map { HudSnapshot.Sky.Point(az: $0.az, alt: $0.alt) }
            return points.contains { $0.alt > 0 } ? points : nil
        }
        sky.constellations = catalogue.constellations.compactMap { label in
            let p = local(label.ra, label.dec)
            return p.alt > 5 ? .init(az: p.az, alt: p.alt, name: label.name) : nil
        }
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

/// The star catalogue, read once from the bundle: stars to magnitude 5.5, the constellation
/// figures, and names for the brightest.
final class SkyCatalogue: @unchecked Sendable {
    struct Star { var ra: Float; var dec: Float; var mag: Float; var bv: Float }
    struct Point { var ra: Float; var dec: Float }
    struct Label { var ra: Float; var dec: Float; var name: String }

    let stars: [Star]
    let lines: [[Point]]
    let constellations: [Label]
    let names: [Label]

    static let shared: SkyCatalogue? = {
        guard let url = Bundle.module.url(forResource: "sky", withExtension: "json",
                                          subdirectory: "Sky"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? SkyCatalogue(json: data)
    }()

    init(json: Data) throws {
        struct Raw: Decodable {
            var stars: [[Float]]
            var lines: [[[Float]]]
            var labels: [[Label3]]
            var names: [[Label3]]
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
        lines = raw.lines.map { $0.compactMap { $0.count >= 2 ? Point(ra: $0[0], dec: $0[1]) : nil } }
        func label(_ row: [Label3]) -> Label? {
            row.count >= 3 ? Label(ra: row[0].number, dec: row[1].number, name: row[2].text) : nil
        }
        constellations = raw.labels.compactMap(label)
        names = raw.names.compactMap(label)
    }
}
