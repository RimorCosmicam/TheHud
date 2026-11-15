import Foundation
import CoreLocation

/// Where the weather comes from.
///
/// A protocol rather than a direct call because the choice is a real trade-off, not a detail.
/// WeatherKit is the native option, but it needs a paid Apple Developer account, an App ID with
/// the capability enabled, an entitlement, and display attribution — none of which a free account
/// or an unsigned CI build can provide. Open-Meteo needs no account and no key, so the HUD works
/// today and the preview tool can fetch the same data on a Mac.
///
/// The privacy difference is worth stating plainly: WeatherKit keeps the request inside Apple's
/// privacy policy, while Open-Meteo means the device's coordinates go to a third party. For a
/// personal build that is a fair trade; before shipping to anyone else, prefer WeatherKit.
public protocol WeatherProviding: Sendable {
    func weather(at coordinate: CLLocationCoordinate2D,
                 placeName: String) async throws -> HudSnapshot.Weather
}

public struct OpenMeteoWeatherProvider: WeatherProviding {
    public init() {}

    public func weather(at coordinate: CLLocationCoordinate2D,
                        placeName: String) async throws -> HudSnapshot.Weather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]

        var request = URLRequest(url: components.url!)
        // No identifying header: the service needs the coordinates and nothing else.
        request.setValue("TheHud", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let code = WeatherCode(rawValue: decoded.current.weather_code) ?? .unknown

        return HudSnapshot.Weather(
            temperature: Int(decoded.current.temperature_2m.rounded()),
            condition: code.label,
            symbol: code.symbol,
            high: Int((decoded.daily.temperature_2m_max.first ?? 0).rounded()),
            low: Int((decoded.daily.temperature_2m_min.first ?? 0).rounded()),
            place: placeName.uppercased())
    }

    public enum WeatherError: Error, CustomStringConvertible {
        case badResponse(Int)
        public var description: String {
            switch self {
            case .badResponse(let code): return "weather request failed with status \(code)"
            }
        }
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }
}

/// WMO weather codes, which is what Open-Meteo reports, mapped to a label and an SF Symbol.
public enum WeatherCode: Int, Sendable {
    case clear = 0
    case mainlyClear = 1
    case partlyCloudy = 2
    case overcast = 3
    case fog = 45
    case rimeFog = 48
    case lightDrizzle = 51
    case drizzle = 53
    case heavyDrizzle = 55
    case lightRain = 61
    case rain = 63
    case heavyRain = 65
    case lightSnow = 71
    case snow = 73
    case heavySnow = 75
    case showers = 80
    case heavyShowers = 82
    case thunderstorm = 95
    case hailstorm = 99
    case unknown = -1

    public var label: String {
        switch self {
        case .clear: return "CLEAR"
        case .mainlyClear: return "MAINLY CLEAR"
        case .partlyCloudy: return "PARTLY CLOUDY"
        case .overcast: return "OVERCAST"
        case .fog, .rimeFog: return "FOG"
        case .lightDrizzle, .drizzle, .heavyDrizzle: return "DRIZZLE"
        case .lightRain: return "LIGHT RAIN"
        case .rain: return "RAIN"
        case .heavyRain: return "HEAVY RAIN"
        case .lightSnow, .snow, .heavySnow: return "SNOW"
        case .showers, .heavyShowers: return "SHOWERS"
        case .thunderstorm: return "THUNDERSTORM"
        case .hailstorm: return "HAIL"
        case .unknown: return "\u{2014}"
        }
    }

    public var symbol: String {
        switch self {
        case .clear, .mainlyClear: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .overcast: return "cloud"
        case .fog, .rimeFog: return "cloud.fog"
        case .lightDrizzle, .drizzle, .heavyDrizzle: return "cloud.drizzle"
        case .lightRain, .rain: return "cloud.rain"
        case .heavyRain, .showers, .heavyShowers: return "cloud.heavyrain"
        case .lightSnow, .snow, .heavySnow: return "cloud.snow"
        case .thunderstorm: return "cloud.bolt.rain"
        case .hailstorm: return "cloud.hail"
        case .unknown: return "questionmark"
        }
    }
}
