import Foundation
import CoreLocation

/// Air quality, UV and pollen from Open-Meteo's air quality service: the same provider, and the
/// same trade (no key, coordinates to a third party), as the weather.
public enum AirQualityProvider {
    public static func air(at coordinate: CLLocationCoordinate2D) async throws -> HudSnapshot.Weather.Air {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            .init(name: "current", value: "european_aqi,pm2_5,uv_index," + pollenKeys.joined(separator: ",")),
            .init(name: "timezone", value: "auto"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("TheHud", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenMeteoWeatherProvider.WeatherError.badResponse(
                (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try decode(data)
    }

    static let pollenKeys = ["alder_pollen", "birch_pollen", "grass_pollen", "mugwort_pollen",
                             "olive_pollen", "ragweed_pollen"]

    public static func decode(_ data: Data) throws -> HudSnapshot.Weather.Air {
        let current = try JSONDecoder().decode(LenientResponse.self, from: data).current
        let index = Int((current["european_aqi"] ?? 0).rounded())
        let uv = current["uv_index"] ?? 0
        // Pollen is only measured in Europe; elsewhere the values are missing, and so is the line.
        let pollen = pollenKeys.compactMap { key in current[key].map { (key, $0) } }
            .max { $0.1 < $1.1 }
            .map { key, grains in
                key.replacingOccurrences(of: "_pollen", with: "").uppercased()
                    + " \u{00B7} " + pollenLevel(grains)
            }
        return HudSnapshot.Weather.Air(index: index, label: aqiLabel(index), uv: uv,
                                       uvLabel: uvLabel(uv), pm25: current["pm2_5"],
                                       pollen: pollen)
    }

    /// The current block, keeping only numbers: nulls (no pollen here) and the time drop out.
    private struct LenientResponse: Decodable {
        var current: [String: Double]
        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Key.self)
            let block = try root.nestedContainer(keyedBy: Key.self, forKey: Key("current"))
            var values: [String: Double] = [:]
            for key in block.allKeys {
                if let value = try? block.decode(Double.self, forKey: key) { values[key.stringValue] = value }
            }
            current = values
        }
        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ string: String) { stringValue = string }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
    }

    /// The European AQI's bands.
    public static func aqiLabel(_ index: Int) -> String {
        switch index {
        case ..<20: return "GOOD"
        case ..<40: return "FAIR"
        case ..<60: return "MODERATE"
        case ..<80: return "POOR"
        case ..<100: return "VERY POOR"
        default: return "EXTREMELY POOR"
        }
    }

    /// The WHO's UV bands.
    public static func uvLabel(_ uv: Double) -> String {
        switch uv {
        case ..<3: return "LOW"
        case ..<6: return "MODERATE"
        case ..<8: return "HIGH"
        case ..<11: return "VERY HIGH"
        default: return "EXTREME"
        }
    }

    /// Grains per cubic metre, in the bands most European services use.
    static func pollenLevel(_ grains: Double) -> String {
        switch grains {
        case ..<1: return "NONE"
        case ..<20: return "LOW"
        case ..<100: return "MODERATE"
        default: return "HIGH"
        }
    }
}
