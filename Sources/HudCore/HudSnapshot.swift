import Foundation
import CoreGraphics

/// Everything the glasses canvas draws, in one value.
///
/// The app fills this from EventKit, WeatherKit, CoreLocation and the browser's own state; the
/// preview fills it with fixed numbers. The views cannot tell the difference, which is what keeps
/// a still honest about what the device will show.
public struct HudSnapshot: Sendable {
    public var clock: Clock
    public var weather: Weather
    public var minimap: Minimap
    public var browser: Browser
    /// Where the trackpad has put the pointer, in canvas points. Nil hides it.
    public var cursor: CGPoint?

    public init(clock: Clock = .preview,
                weather: Weather = .preview,
                minimap: Minimap = .preview,
                browser: Browser = .preview,
                cursor: CGPoint? = CGPoint(x: 1180, y: 520)) {
        self.clock = clock
        self.weather = weather
        self.minimap = minimap
        self.browser = browser
        self.cursor = cursor
    }

    public struct Clock: Sendable {
        public var time: String
        public var meridiem: String?
        public var weekday: String
        public var date: String
        /// The next calendar event, if there is one worth saying.
        public var nextEvent: String?
        public var nextEventTime: String?

        public init(time: String, meridiem: String? = nil, weekday: String, date: String,
                    nextEvent: String? = nil, nextEventTime: String? = nil) {
            self.time = time
            self.meridiem = meridiem
            self.weekday = weekday
            self.date = date
            self.nextEvent = nextEvent
            self.nextEventTime = nextEventTime
        }

        public static let preview = Clock(time: "9:41", weekday: "WEDNESDAY", date: "15 NOVEMBER",
                                          nextEvent: "Design review", nextEventTime: "10:30")
    }

    public struct Weather: Sendable {
        public var temperature: Int
        public var condition: String
        public var symbol: String
        public var high: Int
        public var low: Int
        public var place: String

        public init(temperature: Int, condition: String, symbol: String,
                    high: Int, low: Int, place: String) {
            self.temperature = temperature
            self.condition = condition
            self.symbol = symbol
            self.high = high
            self.low = low
            self.place = place
        }

        public static let preview = Weather(temperature: 12, condition: "LIGHT RAIN",
                                            symbol: "cloud.drizzle", high: 14, low: 7,
                                            place: "LISBON")
    }

    public struct Minimap: Sendable {
        public var place: String
        /// Degrees clockwise from north.
        public var heading: Double
        public var headingLabel: String
        public var speed: String
        /// Metres across the short edge of the panel, for the scale bar.
        public var spanMetres: Int

        public init(place: String, heading: Double, headingLabel: String,
                    speed: String, spanMetres: Int) {
            self.place = place
            self.heading = heading
            self.headingLabel = headingLabel
            self.speed = speed
            self.spanMetres = spanMetres
        }

        public static let preview = Minimap(place: "ALFAMA", heading: 34, headingLabel: "NE",
                                            speed: "4.2 KM/H", spanMetres: 300)
    }

    public struct Browser: Sendable {
        public var url: String
        public var title: String
        public var tabs: [String]
        public var activeTab: Int
        public var loading: Double?

        public init(url: String, title: String, tabs: [String], activeTab: Int,
                    loading: Double? = nil) {
            self.url = url
            self.title = title
            self.tabs = tabs
            self.activeTab = activeTab
            self.loading = loading
        }

        public static let preview = Browser(url: "developer.apple.com/documentation/uikit",
                                            title: "UIKit | Apple Developer Documentation",
                                            tabs: ["UIKit", "Metal Shading Language", "Xreal"],
                                            activeTab: 0)
    }
}
