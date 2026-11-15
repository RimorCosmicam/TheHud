import Foundation
import CoreGraphics

/// Everything the glasses canvas draws, in one value.
///
/// The app fills this from EventKit, WeatherKit, CoreLocation and the browser's own state; the
/// preview fills it with fixed numbers. The views cannot tell the difference, which is what keeps
/// a still honest about what the device will show.
public struct HudSnapshot: Sendable {
    public var clock: Clock
    /// Nil until a reading has actually arrived; the panel is dropped rather than faked.
    public var weather: Weather?
    public var minimap: Minimap
    /// The Maps app: search, results, and the route being followed.
    public var maps: Maps = Maps()
    /// The Mac streamed by HudCast.
    public var desktop: Desktop = Desktop()
    /// The clock app's timer, as it reads this second.
    public var timer: TimerReading = TimerReading()
    /// Steps today. Nil where the phone cannot count them, or before it has.
    public var activity: Activity? = .preview
    public var sky: Sky = Sky()
    /// What the Music app is playing. Nil when nothing is queued.
    public var music: NowPlaying? = .preview
    public var note: Note = .preview
    public var captions: Captions = .preview
    public var browser: Browser
    /// Where the trackpad has put the pointer, in canvas points. Nil hides it.
    public var cursor: CGPoint?

    public init(clock: Clock = .preview,
                weather: Weather? = .preview,
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
        /// "07", for the clock app's seconds.
        public var seconds: String = "00"
        /// Hours (0..<12), minutes and seconds as fractions, for the dial's hands.
        public var hourHand: Double = 0
        public var minuteHand: Double = 0
        public var secondHand: Double = 0
        /// The rest of today's calendar, earliest first, for the clock app.
        public var agenda: [Event] = []
        public var worldClocks: [WorldClock] = []

        public init(time: String, meridiem: String? = nil, weekday: String, date: String,
                    nextEvent: String? = nil, nextEventTime: String? = nil) {
            self.time = time
            self.meridiem = meridiem
            self.weekday = weekday
            self.date = date
            self.nextEvent = nextEvent
            self.nextEventTime = nextEventTime
        }

        public struct Event: Sendable, Hashable {
            public var title: String
            /// "10:30", or "ALL DAY".
            public var time: String
            public var end: String?
            /// Happening right now.
            public var isNow: Bool
            public init(title: String, time: String, end: String? = nil, isNow: Bool = false) {
                self.title = title
                self.time = time
                self.end = end
                self.isNow = isNow
            }
        }

        public struct WorldClock: Sendable, Hashable {
            public var city: String
            public var time: String
            /// "+4H", "TOMORROW", relative to here.
            public var offset: String
            /// Between 7am and 7pm there, for a sun or a moon.
            public var isDay: Bool
            public init(city: String, time: String, offset: String, isDay: Bool) {
                self.city = city
                self.time = time
                self.offset = offset
                self.isDay = isDay
            }
        }

        public static let preview: Clock = {
            var clock = Clock(time: "9:41", weekday: "WEDNESDAY", date: "15 NOVEMBER",
                              nextEvent: "Design review", nextEventTime: "10:30")
            clock.seconds = "07"
            clock.hourHand = 9 + 41 / 60.0
            clock.minuteHand = 41 + 7 / 60.0
            clock.secondHand = 7
            clock.agenda = [
                Event(title: "Stand-up", time: "9:30", end: "9:45", isNow: true),
                Event(title: "Design review", time: "10:30", end: "11:30"),
                Event(title: "Lunch with Ana", time: "13:00", end: "14:00"),
                Event(title: "Ship the HUD", time: "17:00", end: "18:00"),
            ]
            clock.worldClocks = [
                WorldClock(city: "NEW YORK", time: "7:41", offset: "\u{2212}2H", isDay: true),
                WorldClock(city: "LONDON", time: "12:41", offset: "+3H", isDay: true),
                WorldClock(city: "TOKYO", time: "21:41", offset: "+12H", isDay: false),
            ]
            return clock
        }()
    }

    public struct Weather: Sendable {
        public var temperature: Int
        public var condition: String
        public var symbol: String
        public var high: Int
        public var low: Int
        public var place: String
        // The forecast, for the weather app. Empty until a reading carries it.
        public var feelsLike: Int?
        public var humidity: Int?
        public var windKmh: Int?
        public var sunrise: String?
        public var sunset: String?
        public var hourly: [Hour] = []
        public var daily: [Day] = []
        /// Air quality, UV and pollen, for the weather app. Nil until a reading arrives.
        public var air: Air?

        public struct Air: Sendable, Hashable {
            /// European AQI: 0-20 good ... over 100 extremely poor.
            public var index: Int
            public var label: String
            public var uv: Double
            public var uvLabel: String
            public var pm25: Double?
            /// "GRASS · MODERATE": the strongest pollen, where it is measured.
            public var pollen: String?
            public init(index: Int, label: String, uv: Double, uvLabel: String,
                        pm25: Double? = nil, pollen: String? = nil) {
                self.index = index
                self.label = label
                self.uv = uv
                self.uvLabel = uvLabel
                self.pm25 = pm25
                self.pollen = pollen
            }
        }

        public init(temperature: Int, condition: String, symbol: String,
                    high: Int, low: Int, place: String) {
            self.temperature = temperature
            self.condition = condition
            self.symbol = symbol
            self.high = high
            self.low = low
            self.place = place
        }

        public struct Hour: Sendable, Hashable {
            /// "NOW", "14", "3PM".
            public var label: String
            public var temperature: Int
            public var symbol: String
            /// Chance of rain, percent.
            public var precipitation: Int
            public init(label: String, temperature: Int, symbol: String, precipitation: Int) {
                self.label = label
                self.temperature = temperature
                self.symbol = symbol
                self.precipitation = precipitation
            }
        }

        public struct Day: Sendable, Hashable {
            /// "TODAY", "THU".
            public var label: String
            public var symbol: String
            public var high: Int
            public var low: Int
            public var precipitation: Int
            public init(label: String, symbol: String, high: Int, low: Int, precipitation: Int) {
                self.label = label
                self.symbol = symbol
                self.high = high
                self.low = low
                self.precipitation = precipitation
            }
        }

        public static let preview: Weather = {
            var weather = Weather(temperature: 12, condition: "LIGHT RAIN",
                                  symbol: "cloud.drizzle", high: 14, low: 7, place: "LISBON")
            weather.feelsLike = 10
            weather.humidity = 82
            weather.windKmh = 18
            weather.air = Air(index: 24, label: "FAIR", uv: 2.1, uvLabel: "LOW", pm25: 8.2,
                              pollen: "GRASS \u{00B7} LOW")
            weather.sunrise = "7:24"
            weather.sunset = "17:21"
            let temps = [12, 12, 13, 14, 14, 13, 12, 11, 10, 10, 9, 9]
            let symbols = ["cloud.drizzle", "cloud.drizzle", "cloud.rain", "cloud", "cloud.sun",
                           "cloud.sun", "cloud", "cloud", "cloud.moon", "moon", "moon", "moon"]
            let rain = [70, 60, 55, 30, 10, 5, 10, 10, 15, 5, 0, 0]
            weather.hourly = (0..<12).map { i in
                Hour(label: i == 0 ? "NOW" : "\(10 + i)", temperature: temps[i],
                     symbol: symbols[i], precipitation: rain[i])
            }
            weather.daily = [
                Day(label: "TODAY", symbol: "cloud.drizzle", high: 14, low: 7, precipitation: 70),
                Day(label: "THU", symbol: "cloud.sun", high: 16, low: 8, precipitation: 10),
                Day(label: "FRI", symbol: "sun.max", high: 19, low: 10, precipitation: 0),
                Day(label: "SAT", symbol: "sun.max", high: 20, low: 11, precipitation: 0),
                Day(label: "SUN", symbol: "cloud", high: 17, low: 11, precipitation: 20),
                Day(label: "MON", symbol: "cloud.heavyrain", high: 13, low: 9, precipitation: 90),
                Day(label: "TUE", symbol: "cloud.rain", high: 12, low: 6, precipitation: 60),
            ]
            return weather
        }()
    }

    public struct Minimap: Sendable {
        public var place: String
        /// Degrees clockwise from north.
        public var heading: Double
        public var headingLabel: String
        public var speed: String
        /// Metres across the short edge of the panel, for the scale bar.
        public var spanMetres: Int
        /// Where the wearer is relative to the centre of the map raster, in metres. The raster
        /// is refetched only every so often; in between it slides under the marker by this much,
        /// so the map moves with every location fix instead of jumping when a new image lands.
        public var groundOffsetEast: Double
        public var groundOffsetNorth: Double
        /// Metres across the current map raster. Larger when the map has the whole canvas, so
        /// the zoom stays the same and the extra room shows more of the area.
        public var groundSpanMetres: Double = 0
        /// The route being followed, in metres east and north of the raster's centre, so it is
        /// drawn in the raster's own frame and turns and slides with it.
        public var route: [CGPoint] = []

        public init(place: String, heading: Double, headingLabel: String,
                    speed: String, spanMetres: Int,
                    groundOffsetEast: Double = 0, groundOffsetNorth: Double = 0) {
            self.place = place
            self.heading = heading
            self.headingLabel = headingLabel
            self.speed = speed
            self.spanMetres = spanMetres
            self.groundOffsetEast = groundOffsetEast
            self.groundOffsetNorth = groundOffsetNorth
        }

        /// The raster covers more ground than the panel shows, so rotating it never exposes a
        /// corner and walking a little way does not run off its edge before the next one comes.
        public static let groundOversize: Double = 1.9

        /// The zoom, fixed: `spanMetres` across a 470pt panel, whatever size the panel is.
        public var pointsPerMetre: Double { 470 / Double(max(spanMetres, 1)) }

        /// The raster's span, or the default for a column-sized panel before one is known.
        public var effectiveGroundSpan: Double {
            groundSpanMetres > 0 ? groundSpanMetres : Double(spanMetres) * Self.groundOversize
        }

        public static let preview = Minimap(place: "ALFAMA", heading: 34, headingLabel: "NE",
                                            speed: "4.2 KM/H", spanMetres: 300)
    }

    /// The timer in the clock app, as drawn: worked out from `HudTimer` each second.
    public struct TimerReading: Sendable, Equatable {
        public enum State: Sendable, Equatable { case idle, running, paused, done }
        public var text: String = "5:00"
        /// 0 at the start, 1 when it runs out. Nil for the stopwatch.
        public var progress: Double? = 0
        public var state: State = .idle
        /// Set to zero: counts up instead.
        public var isStopwatch: Bool = false
        public init() {}
    }

    public struct Activity: Sendable, Equatable {
        public var steps: Int
        public var goal: Int
        public var distanceKm: Double?
        public var floors: Int?
        /// Steps in each hour of today so far, midnight first.
        public var hourly: [Int]
        public init(steps: Int, goal: Int = 8000, distanceKm: Double? = nil, floors: Int? = nil,
                    hourly: [Int] = []) {
            self.steps = steps
            self.goal = goal
            self.distanceKm = distanceKm
            self.floors = floors
            self.hourly = hourly
        }
        public var fraction: Double { min(Double(steps) / Double(max(goal, 1)), 1) }

        public static let preview: Activity = Activity(
            steps: 6_412, goal: 8000, distanceKm: 4.7, floors: 6,
            hourly: [0, 0, 0, 0, 0, 0, 0, 120, 880, 1_240, 310, 460, 920, 1_330, 640, 512])
    }

    public struct NowPlaying: Sendable, Equatable {
        public var title: String
        public var artist: String
        public var album: String
        public var isPlaying: Bool
        public var elapsed: TimeInterval
        public var duration: TimeInterval
        public init(title: String, artist: String, album: String = "", isPlaying: Bool,
                    elapsed: TimeInterval = 0, duration: TimeInterval = 0) {
            self.title = title
            self.artist = artist
            self.album = album
            self.isPlaying = isPlaying
            self.elapsed = elapsed
            self.duration = duration
        }
        public var progress: Double { duration > 0 ? min(elapsed / duration, 1) : 0 }

        public static func time(_ seconds: TimeInterval) -> String {
            let s = max(Int(seconds.rounded(.down)), 0)
            return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                             : String(format: "%d:%02d", s / 60, s % 60)
        }

        public static let preview = NowPlaying(title: "Midnight City", artist: "M83",
                                               album: "Hurry Up, We're Dreaming",
                                               isPlaying: true, elapsed: 97, duration: 243)
    }

    public struct Note: Sendable, Equatable {
        public var text: String
        public var isEditing: Bool = false
        /// How far the fullscreen note is scrolled, in points: a teleprompter.
        public var scroll: CGFloat = 0
        public init(text: String = "") { self.text = text }

        public static let preview = Note(text: "Gate B32, boarding 18:40. Ask Ana about the "
                                         + "slides before Friday. Milk, coffee, batteries.")
    }

    public struct Captions: Sendable, Equatable {
        public var isListening: Bool = false
        /// Finished sentences, oldest first; only the last few are kept here.
        public var lines: [String] = []
        /// What is being said right now, still changing.
        public var partial: String = ""
        /// "LISTENING", "OFF", "NO MICROPHONE ACCESS".
        public var status: String = "OFF"
        /// "12:04", how long this session has run.
        public var elapsed: String = ""
        public init() {}

        public static let preview: Captions = {
            var captions = Captions()
            captions.isListening = true
            captions.status = "LISTENING · PT-BR"
            captions.elapsed = "3:12"
            captions.lines = ["So the plan is to ship the HUD on Friday.",
                              "We still need the icons for the editor,",
                              "and someone should test it on the train."]
            captions.partial = "I can do that tomorrow morning"
            return captions
        }()
    }

    /// The sky over the wearer: the day's sun and moon for the widget, the stars for the app.
    public struct Sky: Sendable {
        public var hasLocation = false
        public var sunrise: String?
        public var sunset: String?
        /// When the evening's golden hour starts: the sun six degrees up.
        public var goldenHour: String?
        /// Through the day, 0 at sunrise and 1 at sunset; nil at night.
        public var dayProgress: Double?
        public var sunAltitude: Double = 0
        public var moonPhase: String = ""
        public var moonSymbol: String = "moonphase.new.moon"
        /// Percent of the disc lit.
        public var moonIllumination: Int = 0
        public var moonrise: String?
        public var moonset: String?
        /// Stars above the horizon, as azimuth and altitude in degrees.
        public var stars: [Star] = []
        /// Constellation figures; points below the horizon are kept so lines can be cut there.
        public var lines: [[Point]] = []
        public var constellations: [Label] = []
        public var starNames: [Label] = []
        /// The sun, the moon and the planets.
        public var bodies: [Body] = []

        public init() {}

        public struct Point: Sendable { public var az: Float; public var alt: Float
            public init(az: Float, alt: Float) { self.az = az; self.alt = alt } }
        public struct Star: Sendable { public var az: Float; public var alt: Float
            public var mag: Float; public var bv: Float
            public init(az: Float, alt: Float, mag: Float, bv: Float) {
                self.az = az; self.alt = alt; self.mag = mag; self.bv = bv } }
        public struct Label: Sendable { public var az: Float; public var alt: Float
            public var name: String
            public init(az: Float, alt: Float, name: String) {
                self.az = az; self.alt = alt; self.name = name } }
        public struct Body: Sendable {
            public enum Kind: Sendable { case sun, moon, planet }
            public var kind: Kind
            public var name: String
            public var az: Double
            public var alt: Double
            public var mag: Double
            public init(kind: Kind, name: String, az: Double, alt: Double, mag: Double) {
                self.kind = kind; self.name = name; self.az = az; self.alt = alt; self.mag = mag
            }
        }
    }

    /// The desktop panel: whether a Mac is there, what it offers and what it is showing.
    public struct Desktop: Sendable, Equatable {
        /// "LOOKING FOR YOUR MAC", "CONNECTING TO STUDIO": said when there is no picture.
        public var status: String = "LOOKING FOR YOUR MAC"
        public var connected: Bool = false
        /// Frames are arriving.
        public var hasPicture: Bool = false
        public var host: String = ""
        public var windows: [DesktopWindow] = []
        public var source: DesktopSource?

        public init() {}

        /// Width over height of what is streaming.
        public var aspect: CGFloat {
            guard let source, source.height > 0 else { return 16 / 10 }
            return CGFloat(source.width) / CGFloat(source.height)
        }

        /// A Mac with a few windows open, streaming the whole screen.
        public static var preview: Desktop {
            var desktop = Desktop()
            desktop.connected = true
            desktop.hasPicture = true
            desktop.host = "Studio"
            desktop.status = ""
            desktop.windows = [
                DesktopWindow(id: 11, app: "Xcode", title: "TheHud — HudController.swift"),
                DesktopWindow(id: 12, app: "Terminal", title: "zsh"),
                DesktopWindow(id: 13, app: "Safari", title: "Apple Developer"),
            ]
            desktop.source = DesktopSource(window: nil, width: 1920, height: 1200, host: "Studio")
            return desktop
        }

        /// Which of `windows` is streaming, or nil for the whole screen.
        public var activeWindow: Int? {
            source?.window.flatMap { id in windows.firstIndex { $0.id == id } }
        }
    }

    /// The Maps app's own state: what is being searched, what was found, where it is going.
    public struct Maps: Sendable {
        /// What has been typed into the search field.
        public var query: String = ""
        /// The search field is taking keystrokes.
        public var isEditing: Bool = false
        public var results: [Place] = []
        /// "SEARCHING", "NO RESULTS", "NO ROUTE": a line that explains an empty list.
        public var status: String?
        public var navigation: Navigation?
        public var driving: Bool = false

        public init() {}

        public struct Place: Sendable, Hashable {
            public var name: String
            public var detail: String
            /// "850 M", "2.4 KM".
            public var distance: String
            public init(name: String, detail: String, distance: String) {
                self.name = name
                self.detail = detail
                self.distance = distance
            }
        }

        /// Turn by turn.
        public struct Navigation: Sendable, Hashable {
            public var destination: String
            /// What to do next: "Turn right onto Rua da Saudade".
            public var instruction: String
            /// An SF Symbol for the turn.
            public var maneuver: String
            /// How far to the turn: "120 M".
            public var stepDistance: String
            /// "12 MIN", "950 M", "14:32".
            public var remainingTime: String
            public var remainingDistance: String
            public var arrival: String
            public var arrived: Bool = false

            public init(destination: String, instruction: String, maneuver: String,
                        stepDistance: String, remainingTime: String, remainingDistance: String,
                        arrival: String) {
                self.destination = destination
                self.instruction = instruction
                self.maneuver = maneuver
                self.stepDistance = stepDistance
                self.remainingTime = remainingTime
                self.remainingDistance = remainingDistance
                self.arrival = arrival
            }
        }

        public static let previewSearch: Maps = {
            var maps = Maps()
            maps.query = "cafe"
            maps.isEditing = true
            maps.results = [
                Place(name: "Café da Garagem", detail: "Costa do Castelo 75", distance: "120 M"),
                Place(name: "Pois, Café", detail: "Rua de São João da Praça 93", distance: "450 M"),
                Place(name: "Copenhagen Coffee Lab", detail: "Rua Nova da Piedade 10", distance: "2.1 KM"),
                Place(name: "Fábrica Coffee Roasters", detail: "Rua das Flores 63", distance: "1.4 KM"),
            ]
            return maps
        }()

        public static let previewNavigation: Maps = {
            var maps = Maps()
            maps.navigation = Navigation(destination: "Miradouro da Graça",
                                         instruction: "Turn right onto Calçada da Graça",
                                         maneuver: "arrow.turn.up.right",
                                         stepDistance: "120 M", remainingTime: "9 MIN",
                                         remainingDistance: "650 M", arrival: "9:50")
            return maps
        }()
    }

    public struct Browser: Sendable {
        public var url: String
        public var title: String
        public var tabs: [String]
        public var activeTab: Int
        public var loading: Double?
        public var canGoBack: Bool
        public var canGoForward: Bool
        /// The address bar is taking keystrokes, so `url` is a draft rather than where we are.
        public var isEditingAddress: Bool
        /// On the start page rather than a site.
        public var isHome: Bool
        /// The current site is one of the favourites.
        public var isFavorite: Bool
        /// The page asked for fullscreen: the browser has the whole canvas.
        public var isFullscreen: Bool = false

        public init(url: String, title: String, tabs: [String], activeTab: Int,
                    loading: Double? = nil, canGoBack: Bool = true, canGoForward: Bool = false,
                    isEditingAddress: Bool = false, isHome: Bool = false,
                    isFavorite: Bool = false) {
            self.isHome = isHome
            self.isFavorite = isFavorite
            self.url = url
            self.title = title
            self.tabs = tabs
            self.activeTab = activeTab
            self.loading = loading
            self.canGoBack = canGoBack
            self.canGoForward = canGoForward
            self.isEditingAddress = isEditingAddress
        }

        public static let preview = Browser(url: "developer.apple.com/documentation/uikit",
                                            title: "UIKit | Apple Developer Documentation",
                                            tabs: ["UIKit", "Metal Shading Language", "Xreal"],
                                            activeTab: 0)
    }

    /// What the device starts from: the time, and nothing it has not actually been told. The
    /// default initialiser is preview data, which must never reach the glasses.
    public static var blank: HudSnapshot {
        var snapshot = HudSnapshot(clock: .now(),
                                   weather: nil,
                                   minimap: Minimap(place: "LOCATING", heading: 0, headingLabel: "",
                                                    speed: "", spanMetres: 300),
                                   browser: Browser(url: "", title: "", tabs: ["New tab"], activeTab: 0,
                                                    canGoBack: false, canGoForward: false, isHome: true),
                                   cursor: nil)
        // Nothing made up on the device: each of these waits for its real source.
        snapshot.activity = nil
        snapshot.music = nil
        snapshot.note = Note()
        snapshot.captions = Captions()
        return snapshot
    }
}
