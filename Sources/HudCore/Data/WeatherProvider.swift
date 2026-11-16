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
            .init(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,"
                  + "relative_humidity_2m,wind_speed_10m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,"
                  + "precipitation_probability_max,sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7"),
        ]

        var request = URLRequest(url: components.url!)
        // No identifying header: the service needs the coordinates and nothing else.
        request.setValue("TheHud", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try Self.decode(data, placeName: placeName)
    }

    /// Open-Meteo's JSON to a reading. Separate from the request so it can be tested offline.
    public static func decode(_ data: Data, placeName: String,
                              locale: Locale = .current) throws -> HudSnapshot.Weather {
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let current = decoded.current
        let code = WeatherCode(rawValue: current.weather_code) ?? .unknown
        let daily = decoded.daily

        var weather = HudSnapshot.Weather(
            temperature: Int(current.temperature_2m.rounded()),
            condition: code.label,
            symbol: code.symbol(isDay: (current.is_day ?? 1) == 1),
            high: Int((daily.temperature_2m_max.first ?? 0).rounded()),
            low: Int((daily.temperature_2m_min.first ?? 0).rounded()),
            place: placeName.uppercased())
        weather.feelsLike = current.apparent_temperature.map { Int($0.rounded()) }
        weather.humidity = current.relative_humidity_2m.map { Int($0.rounded()) }
        weather.windKmh = current.wind_speed_10m.map { Int($0.rounded()) }

        // The times are local to the place (timezone=auto), as plain "2026-11-15T14:00".
        let zone = decoded.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = zone
        parse.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let uses24Hour = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
                          ?? "H").contains("H")
        let hourLabel = DateFormatter()
        hourLabel.locale = Locale(identifier: "en_US_POSIX")
        hourLabel.timeZone = zone
        hourLabel.dateFormat = uses24Hour ? "HH" : "ha"
        let clockLabel = DateFormatter()
        clockLabel.locale = Locale(identifier: "en_US_POSIX")
        clockLabel.timeZone = zone
        clockLabel.dateFormat = uses24Hour ? "H:mm" : "h:mm"

        if let rise = daily.sunrise?.first.flatMap(parse.date(from:)) {
            weather.sunrise = clockLabel.string(from: rise)
        }
        if let set = daily.sunset?.first.flatMap(parse.date(from:)) {
            weather.sunset = clockLabel.string(from: set)
        }

        // The next twelve hours, starting with the one we are in.
        if let hourly = decoded.hourly {
            let nowHour = String(current.time.prefix(13))      // "2026-11-15T14"
            let start = hourly.time.firstIndex { $0.prefix(13) >= nowHour } ?? 0
            weather.hourly = hourly.time.indices.dropFirst(start).prefix(12).map { i in
                let code = WeatherCode(rawValue: hourly.weather_code[i]) ?? .unknown
                let label = i == start ? "NOW"
                    : parse.date(from: hourly.time[i]).map { hourLabel.string(from: $0) } ?? ""
                return .init(label: label,
                             temperature: Int(hourly.temperature_2m[i].rounded()),
                             symbol: code.symbol(isDay: (hourly.is_day?[i] ?? 1) == 1),
                             precipitation: hourly.precipitation_probability?[i] ?? 0)
            }
        }

        let dayLabel = DateFormatter()
        dayLabel.locale = locale
        dayLabel.timeZone = zone
        dayLabel.dateFormat = "EEE"
        let dayParse = DateFormatter()
        dayParse.locale = Locale(identifier: "en_US_POSIX")
        dayParse.timeZone = zone
        dayParse.dateFormat = "yyyy-MM-dd"
        weather.daily = daily.time.indices.map { i in
            let code = WeatherCode(rawValue: daily.weather_code?[i] ?? -1) ?? .unknown
            let label = i == 0 ? "TODAY"
                : dayParse.date(from: daily.time[i]).map {
                    dayLabel.string(from: $0).uppercased().replacingOccurrences(of: ".", with: "")
                } ?? ""
            return .init(label: label, symbol: code.symbol(isDay: true),
                         high: Int(daily.temperature_2m_max[i].rounded()),
                         low: Int(daily.temperature_2m_min[i].rounded()),
                         precipitation: daily.precipitation_probability_max?[i] ?? 0)
        }
        return weather
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
            let time: String
            let temperature_2m: Double
            let weather_code: Int
            let apparent_temperature: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double?
            let is_day: Int?
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let precipitation_probability: [Int]?
            let is_day: [Int]?
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]?
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int]?
            let sunrise: [String]?
            let sunset: [String]?
        }
        let timezone: String?
        let current: Current
        let hourly: Hourly?
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

    /// The symbol, with a moon instead of a sun after dark.
    public func symbol(isDay: Bool) -> String {
        guard !isDay else { return symbol }
        switch self {
        case .clear, .mainlyClear: return "moon.stars"
        case .partlyCloudy: return "cloud.moon"
        default: return symbol
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
