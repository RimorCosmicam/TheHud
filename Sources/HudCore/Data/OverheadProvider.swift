import Foundation

extension HudSnapshot {
    /// What is flying over the wearer: aircraft from adsb.lol's open feed, and the space station
    /// from wheretheiss.at, each placed in the local sky.
    public struct Overhead: Sendable {
        public var planes: [Plane] = []
        public var station: Station?
        /// "" when all is well; otherwise what to say instead of planes.
        public var status: String = ""

        public init() {}

        public struct Point: Sendable, Equatable {
            public var az: Double
            public var alt: Double
            public init(az: Double, alt: Double) { self.az = az; self.alt = alt }
        }

        public struct Plane: Sendable, Identifiable {
            public var id: String
            public var callsign: String
            public var airline: String?
            /// "A320neo", "787-9"; the raw type code when it is not one we know.
            public var model: String?
            /// Metres above sea level.
            public var altitude: Double
            /// Kilometres an hour over the ground.
            public var speed: Double
            /// Straight-line kilometres from the wearer.
            public var distance: Double
            /// Compass direction it is flying, degrees.
            public var track: Double
            public var position: Point
            /// Where it will be in half a minute: which way it moves across the sky.
            public var ahead: Point
            /// Where it has been, oldest first.
            public var trail: [Point]

            public init(id: String, callsign: String, airline: String? = nil, model: String? = nil,
                        altitude: Double, speed: Double, distance: Double, track: Double,
                        position: Point, ahead: Point, trail: [Point] = []) {
                self.id = id; self.callsign = callsign; self.airline = airline; self.model = model
                self.altitude = altitude; self.speed = speed; self.distance = distance
                self.track = track; self.position = position; self.ahead = ahead; self.trail = trail
            }
        }

        public struct Station: Sendable {
            public var position: Point
            /// Kilometres above the ground.
            public var altitude: Double
            public var speed: Double
            public var distance: Double
            /// In the sun's light, so it can shine in a dark sky.
            public var sunlit: Bool
            /// Where it goes over the next few minutes.
            public var path: [Point]

            public init(position: Point, altitude: Double, speed: Double, distance: Double,
                        sunlit: Bool, path: [Point]) {
                self.position = position; self.altitude = altitude; self.speed = speed
                self.distance = distance; self.sunlit = sunlit; self.path = path
            }
        }

        /// Planes over Lisbon on a November night, and the station climbing in the west.
        public static var preview: Overhead {
            var overhead = Overhead()
            func p(_ az: Double, _ alt: Double) -> Point { Point(az: az, alt: alt) }
            overhead.planes = [
                Plane(id: "4951d6", callsign: "TAP1824", airline: "TAP Air Portugal", model: "A320",
                      altitude: 3630, speed: 530, distance: 18, track: 18,
                      position: p(40, 14), ahead: p(36, 15.5), trail: [p(52, 10), p(48, 11.5), p(44, 12.8)]),
                Plane(id: "aea097", callsign: "AEA097", airline: "Air Europa", model: "787-9",
                      altitude: 10670, speed: 850, distance: 52, track: 258,
                      position: p(95, 11), ahead: p(88, 11.6), trail: [p(110, 9), p(104, 9.8), p(99, 10.4)]),
                Plane(id: "ice954", callsign: "ICE954", airline: "Icelandair", model: "737 MAX 8",
                      altitude: 2440, speed: 474, distance: 31, track: 152,
                      position: p(20, 4.5), ahead: p(24, 4.6), trail: [p(12, 4.2), p(15, 4.3), p(18, 4.4)]),
            ]
            overhead.station = Station(position: p(262, 24), altitude: 414, speed: 27_600,
                                       distance: 960, sunlit: true,
                                       path: [p(250, 12), p(256, 18), p(262, 24), p(275, 33),
                                              p(300, 41), p(330, 38), p(350, 28), p(2, 18)])
            return overhead
        }
    }
}

/// Where something in the air is, seen from the ground.
public enum SkyGeometry {
    static let earthRadius = 6_371_000.0

    /// Azimuth and altitude in degrees, and the straight-line distance in metres, of a point at
    /// `height` metres over `latitude`/`longitude`, from an observer on the ground. The earth is
    /// taken as a sphere, which is plenty for where on the glasses a plane goes.
    public static func look(fromLatitude lat0: Double, longitude lon0: Double,
                            toLatitude lat: Double, longitude lon: Double,
                            height: Double) -> (az: Double, alt: Double, distance: Double) {
        func ecef(_ lat: Double, _ lon: Double, _ h: Double) -> (Double, Double, Double) {
            let r = earthRadius + h, φ = lat * .pi / 180, λ = lon * .pi / 180
            return (r * cos(φ) * cos(λ), r * cos(φ) * sin(λ), r * sin(φ))
        }
        let o = ecef(lat0, lon0, 0), t = ecef(lat, lon, height)
        let dx = t.0 - o.0, dy = t.1 - o.1, dz = t.2 - o.2
        let φ = lat0 * .pi / 180, λ = lon0 * .pi / 180
        let east = -sin(λ) * dx + cos(λ) * dy
        let north = -sin(φ) * cos(λ) * dx - sin(φ) * sin(λ) * dy + cos(φ) * dz
        let up = cos(φ) * cos(λ) * dx + cos(φ) * sin(λ) * dy + sin(φ) * dz
        var az = atan2(east, north) * 180 / .pi
        if az < 0 { az += 360 }
        let alt = atan2(up, hypot(east, north)) * 180 / .pi
        return (az, alt, (dx * dx + dy * dy + dz * dz).squareRoot())
    }

    /// Where something at `latitude`/`longitude` ends up after `metres` along `track` degrees.
    public static func move(latitude: Double, longitude: Double, track: Double,
                            metres: Double) -> (latitude: Double, longitude: Double) {
        let t = track * .pi / 180
        let lat = latitude + metres * cos(t) / 111_320
        let lon = longitude + metres * sin(t) / (111_320 * max(cos(latitude * .pi / 180), 0.01))
        return (lat, lon)
    }
}

/// Fetches and keeps the aircraft and the station, and places them for any moment in between
/// fetches by flying them on along their tracks.
@MainActor
public final class OverheadProvider {
    struct Fix { var latitude: Double; var longitude: Double; var altitude: Double }
    struct Track {
        var callsign: String
        var model: String?
        var fix: Fix
        /// Metres a second.
        var speed: Double
        var track: Double
        var climb: Double
        var at: Date
        var history: [Fix]
    }
    struct StationFix { var at: Date; var latitude: Double; var longitude: Double; var altitude: Double
        var speed: Double; var sunlit: Bool }

    private var tracks: [String: Track] = [:]
    private var station: [StationFix] = []
    private var status = ""
    private var lastPlanes: Date = .distantPast
    private var lastStation: Date = .distantPast
    private var fetchingPlanes = false
    private var fetchingStation = false

    /// Nautical miles: about 150 km, as far as a cruising airliner still clears the horizon.
    static let radius = 80

    public init() {}

    /// Fetches what is due: planes every 15 seconds, the station's next minutes every minute.
    public func refresh(latitude: Double, longitude: Double, planes: Bool, station wantsStation: Bool,
                        now: Date = Date()) {
        if planes, !fetchingPlanes, now.timeIntervalSince(lastPlanes) > 15 {
            fetchingPlanes = true
            lastPlanes = now
            Task {
                await fetchPlanes(latitude: latitude, longitude: longitude)
                fetchingPlanes = false
            }
        }
        if wantsStation, !fetchingStation, now.timeIntervalSince(lastStation) > 60 {
            fetchingStation = true
            lastStation = now
            Task {
                await fetchStation(now: now)
                fetchingStation = false
            }
        }
    }

    private func fetchPlanes(latitude: Double, longitude: Double) async {
        // Rounded to a kilometre or so: the feed needs where to look, not where you stand.
        let lat = (latitude * 100).rounded() / 100, lon = (longitude * 100).rounded() / 100
        guard let url = URL(string: "https://api.adsb.lol/v2/point/\(lat)/\(lon)/\(Self.radius)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            apply(planes: try Self.decodePlanes(data), at: Date())
            status = ""
        } catch {
            if tracks.isEmpty { status = "NO FLIGHT DATA" }
        }
    }

    struct Reported { var id: String; var callsign: String; var model: String?; var fix: Fix
        var speed: Double; var track: Double; var climb: Double; var age: Double }

    /// adsb.lol's `ac` list, ADS-B Exchange's format. Anything on the ground or without a
    /// position is left out; every field is optional there.
    static func decodePlanes(_ data: Data) throws -> [Reported] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["ac"] as? [[String: Any]] else { return [] }
        return list.compactMap { ac in
            guard let id = ac["hex"] as? String,
                  let lat = ac["lat"] as? Double, let lon = ac["lon"] as? Double,
                  let feet = (ac["alt_geom"] as? Double) ?? (ac["alt_baro"] as? Double),
                  feet > 50 else { return nil }
            let callsign = (ac["flight"] as? String)?.trimmingCharacters(in: .whitespaces)
            return Reported(id: id,
                            callsign: (callsign?.isEmpty == false ? callsign : nil)
                                ?? (ac["r"] as? String) ?? id.uppercased(),
                            model: ac["t"] as? String,
                            fix: Fix(latitude: lat, longitude: lon, altitude: feet * 0.3048),
                            speed: ((ac["gs"] as? Double) ?? 0) * 0.514444,
                            track: (ac["track"] as? Double) ?? 0,
                            climb: ((ac["geom_rate"] as? Double) ?? (ac["baro_rate"] as? Double) ?? 0)
                                * 0.3048 / 60,
                            age: (ac["seen_pos"] as? Double) ?? 0)
        }
    }

    private func apply(planes: [Reported], at now: Date) {
        var next: [String: Track] = [:]
        for plane in planes {
            var history = tracks[plane.id].map { $0.history + [$0.fix] } ?? []
            history = Array(history.suffix(5))
            next[plane.id] = Track(callsign: plane.callsign, model: plane.model, fix: plane.fix,
                                   speed: plane.speed, track: plane.track, climb: plane.climb,
                                   at: now.addingTimeInterval(-plane.age), history: history)
        }
        tracks = next
    }

    private func fetchStation(now: Date) async {
        // Its next six minutes, 45 seconds apart, to fly it between fetches and draw its way.
        let start = Int(now.timeIntervalSince1970) - 15
        let stamps = (0..<10).map { String(start + $0 * 45) }.joined(separator: ",")
        guard let url = URL(string: "https://api.wheretheiss.at/v1/satellites/25544/positions?timestamps=\(stamps)&units=kilometers")
        else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let fixes = try Self.decodeStation(data)
            if !fixes.isEmpty { station = fixes }
        } catch {}
    }

    static func decodeStation(_ data: Data) throws -> [StationFix] {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let lat = row["latitude"] as? Double, let lon = row["longitude"] as? Double,
                  let alt = row["altitude"] as? Double, let stamp = row["timestamp"] as? Double
            else { return nil }
            return StationFix(at: Date(timeIntervalSince1970: stamp), latitude: lat, longitude: lon,
                              altitude: alt, speed: (row["velocity"] as? Double) ?? 27_600,
                              sunlit: (row["visibility"] as? String) != "eclipsed")
        }
        .sorted { $0.at < $1.at }
    }

    /// Everything placed in the sky over `latitude`/`longitude` at `now`.
    public func overhead(latitude: Double, longitude: Double, now: Date = Date()) -> HudSnapshot.Overhead {
        var overhead = HudSnapshot.Overhead()
        overhead.status = status
        func look(_ fix: Fix) -> (point: HudSnapshot.Overhead.Point, distance: Double) {
            let l = SkyGeometry.look(fromLatitude: latitude, longitude: longitude,
                                     toLatitude: fix.latitude, longitude: fix.longitude,
                                     height: fix.altitude)
            return (.init(az: l.az, alt: l.alt), l.distance)
        }
        func flown(_ track: Track, seconds: Double) -> Fix {
            let moved = SkyGeometry.move(latitude: track.fix.latitude, longitude: track.fix.longitude,
                                         track: track.track, metres: track.speed * seconds)
            return Fix(latitude: moved.latitude, longitude: moved.longitude,
                       altitude: max(track.fix.altitude + track.climb * seconds, 0))
        }
        for (id, track) in tracks {
            // Not flown on for ever: a plane the feed has lost stops where it was last seen.
            let age = min(max(now.timeIntervalSince(track.at), 0), 60)
            let fix = flown(track, seconds: age)
            let here = look(fix)
            guard here.point.alt > -1 else { continue }
            let ahead = look(flown(track, seconds: age + 30)).point
            overhead.planes.append(.init(
                id: id, callsign: track.callsign, airline: Aviation.airline(track.callsign),
                model: track.model.map(Aviation.model), altitude: fix.altitude,
                speed: track.speed * 3.6, distance: here.distance / 1000, track: track.track,
                position: here.point, ahead: ahead,
                trail: (track.history + [fix]).map { look($0).point }))
        }
        overhead.planes.sort { $0.distance < $1.distance }

        if let now = stationFix(at: now) {
            let here = look(Fix(latitude: now.latitude, longitude: now.longitude, altitude: now.altitude * 1000))
            overhead.station = .init(
                position: here.point, altitude: now.altitude, speed: now.speed,
                distance: here.distance / 1000, sunlit: now.sunlit,
                path: station.map { look(Fix(latitude: $0.latitude, longitude: $0.longitude,
                                             altitude: $0.altitude * 1000)).point })
        }
        return overhead
    }

    /// The station between two of its fixes, or nil once they have run out.
    private func stationFix(at date: Date) -> StationFix? {
        guard let after = station.firstIndex(where: { $0.at > date }), after > 0 else { return nil }
        let a = station[after - 1], b = station[after]
        let t = date.timeIntervalSince(a.at) / b.at.timeIntervalSince(a.at)
        var dLon = b.longitude - a.longitude
        if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
        var lon = a.longitude + dLon * t
        if lon > 180 { lon -= 360 } else if lon < -180 { lon += 360 }
        return StationFix(at: date, latitude: a.latitude + (b.latitude - a.latitude) * t,
                          longitude: lon, altitude: a.altitude + (b.altitude - a.altitude) * t,
                          speed: a.speed, sunlit: a.sunlit)
    }
}

/// Names for the codes the feed gives: airlines by the three letters a callsign starts with,
/// aircraft by their ICAO type designator. The common ones only; others show as they come.
public enum Aviation {
    public static func airline(_ callsign: String) -> String? {
        let prefix = String(callsign.prefix(3)).uppercased()
        guard prefix.count == 3, prefix.allSatisfy(\.isLetter),
              callsign.dropFirst(3).first?.isNumber ?? false else { return nil }
        return airlines[prefix]
    }

    public static func model(_ code: String) -> String { models[code.uppercased()] ?? code }

    static let airlines: [String: String] = [
        "TAP": "TAP Air Portugal", "RYR": "Ryanair", "EZY": "easyJet", "EJU": "easyJet Europe",
        "EZS": "easyJet Switzerland", "VLG": "Vueling", "IBE": "Iberia", "IBS": "Iberia Express",
        "ANE": "Air Nostrum", "AEA": "Air Europa", "BAW": "British Airways", "VIR": "Virgin Atlantic",
        "EIN": "Aer Lingus", "AFR": "Air France", "KLM": "KLM", "TRA": "Transavia",
        "TVF": "Transavia France", "DLH": "Lufthansa", "EWG": "Eurowings", "SWR": "Swiss",
        "AUA": "Austrian", "BEL": "Brussels Airlines", "ITY": "ITA Airways", "SAS": "SAS",
        "FIN": "Finnair", "ICE": "Icelandair", "NAX": "Norwegian", "NSZ": "Norwegian",
        "WZZ": "Wizz Air", "LOT": "LOT", "AEE": "Aegean", "BTI": "airBaltic", "LGL": "Luxair",
        "THY": "Turkish Airlines", "PGT": "Pegasus", "UAE": "Emirates", "QTR": "Qatar Airways",
        "ETD": "Etihad", "SVA": "Saudia", "MSR": "EgyptAir", "RAM": "Royal Air Maroc",
        "ETH": "Ethiopian", "SAA": "South African", "UAL": "United", "AAL": "American",
        "DAL": "Delta", "SWA": "Southwest", "JBU": "JetBlue", "ACA": "Air Canada",
        "WJA": "WestJet", "AMX": "Aeroméxico", "AVA": "Avianca", "LAN": "LATAM",
        "TAM": "LATAM Brasil", "LPE": "LATAM Peru", "GLO": "Gol", "AZU": "Azul",
        "PTB": "Voepass", "ARG": "Aerolíneas Argentinas", "CMP": "Copa", "SKU": "Sky Airline",
        "ANA": "All Nippon", "JAL": "Japan Airlines", "CPA": "Cathay Pacific",
        "SIA": "Singapore Airlines", "QFA": "Qantas", "KAL": "Korean Air",
        "CES": "China Eastern", "CSN": "China Southern", "CCA": "Air China",
        "FDX": "FedEx", "UPS": "UPS", "DHK": "DHL", "BCS": "DHL", "GEC": "Lufthansa Cargo",
        "CLX": "Cargolux", "NJE": "NetJets", "EJA": "NetJets", "SAT": "Azores Airlines",
        "RZO": "Azores Airlines", "BCY": "CityJet", "VOE": "Volotea", "CFG": "Condor",
    ]

    static let models: [String: String] = [
        "A319": "A319", "A320": "A320", "A321": "A321", "A20N": "A320neo", "A21N": "A321neo",
        "A19N": "A319neo", "BCS1": "A220-100", "BCS3": "A220-300", "A332": "A330-200",
        "A333": "A330-300", "A338": "A330-800neo", "A339": "A330-900neo", "A359": "A350-900",
        "A35K": "A350-1000", "A388": "A380", "B737": "737-700", "B738": "737-800",
        "B739": "737-900", "B37M": "737 MAX 7", "B38M": "737 MAX 8", "B39M": "737 MAX 9",
        "B3XM": "737 MAX 10", "B752": "757-200", "B763": "767-300", "B772": "777-200",
        "B77W": "777-300ER", "B77L": "777-200LR", "B788": "787-8", "B789": "787-9",
        "B78X": "787-10", "B744": "747-400", "B748": "747-8", "E170": "E170", "E75L": "E175",
        "E190": "E190", "E195": "E195", "E290": "E190-E2", "E295": "E195-E2", "AT72": "ATR 72",
        "AT75": "ATR 72-500", "AT76": "ATR 72-600", "DH8D": "Dash 8-400", "CRJ9": "CRJ900",
        "C172": "Cessna 172", "C152": "Cessna 152", "P28A": "Piper Cherokee", "PC12": "Pilatus PC-12",
        "GLF6": "Gulfstream G650", "GLEX": "Global Express", "C68A": "Citation Latitude",
        "EC35": "H135 helicopter", "EC45": "H145 helicopter", "A139": "AW139 helicopter",
    ]
}
