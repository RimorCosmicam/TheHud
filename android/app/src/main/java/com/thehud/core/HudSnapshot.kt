package com.thehud.core

import androidx.compose.ui.geometry.Offset
import kotlinx.serialization.Serializable
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Everything the glasses draw, in one value: the glasses are a picture of this. */
data class HudSnapshot(
    val clock: Clock = Clock.preview,
    /** Null until a reading has actually arrived; the panel says so rather than faking one. */
    val weather: Weather? = Weather.preview,
    val minimap: Minimap = Minimap.preview,
    val maps: Maps = Maps(),
    val desktop: Desktop = Desktop(),
    val timer: TimerReading = TimerReading(),
    /** Steps today. Null where the phone cannot count them, or before it has. */
    val activity: Activity? = Activity.preview,
    val sky: Sky = Sky(),
    val overhead: Overhead = Overhead(),
    val skyView: SkyView = SkyView(),
    /** What is playing. Null when nothing is. */
    val music: NowPlaying? = NowPlaying.preview,
    val note: Note = Note(),
    val captions: Captions = Captions.preview,
    val youtube: YouTube = YouTube.preview,
    val browser: Browser = Browser(),
    /** Today and this month, from the phone's calendars. */
    val agenda: Agenda = Agenda.preview,
    /** The photo library; the pictures come separately, by index. */
    val photos: Photos = Photos.preview,
    /** The teleprompter, which reads the note. */
    val prompter: Prompter = Prompter(),
    /** Where the pointer is, in canvas points. Null hides it. */
    val cursor: Offset? = null,
) {
    /** Today and this month, from the phone's calendars: the calendar app, as the iPhone's. */
    data class Agenda(
        /** False until the calendars may be read; the app says so rather than showing nothing. */
        val hasAccess: Boolean = true,
        /** "MONDAY · 16 NOVEMBER". */
        val dayTitle: String = "",
        /** Today, all-day first, then by start. */
        val today: List<Entry> = emptyList(),
        /** Minutes since midnight, for the timeline's now line. */
        val nowMinute: Int = 0,
        /** What comes next (or is on now), and how soon: "IN 25 MIN", "NOW", "AT 18:40". */
        val next: Entry? = null,
        val nextIn: String = "",
        val later: List<Entry> = emptyList(),
        /** "NOVEMBER 2026". */
        val monthTitle: String = "",
        /** "MON" … "SUN", in the order the phone's calendar starts its week. */
        val weekdays: List<String> = emptyList(),
        /** Whole weeks covering the month: 35 or 42 days. */
        val days: List<Day> = emptyList(),
    ) {
        data class Entry(val title: String, val time: String, val endTime: String = "", val startMinute: Int = 0,
                         val endMinute: Int = 0, val allDay: Boolean = false, val location: String = "", val tint: Int = 0)
        data class Day(val number: Int, val inMonth: Boolean = true, val isToday: Boolean = false,
                       val titles: List<String> = emptyList(), val more: Int = 0)

        companion object {
            val preview: Agenda = run {
                val today = listOf(
                    Entry("Ana's birthday", "ALL DAY", allDay = true, tint = 2),
                    Entry("Stand-up", "09:00", "09:15", 540, 555, tint = 0),
                    Entry("Design review", "10:30", "11:30", 630, 690, location = "Room 4", tint = 1),
                    Entry("Lunch with Rui", "13:00", "14:00", 780, 840, location = "Time Out Market", tint = 3),
                    Entry("Ship the HUD build", "16:00", "17:30", 960, 1050, tint = 0),
                    Entry("Flight to Porto", "18:40", "19:40", 1120, 1180, location = "Gate B32", tint = 4),
                )
                val sample = mapOf(3 to listOf("Dentist"), 7 to listOf("Market"), 10 to listOf("Review", "Gym"),
                    15 to listOf("Design review", "Lunch with Rui", "Ship"), 18 to listOf("Porto"), 19 to listOf("Porto"),
                    21 to listOf("Dinner"), 24 to listOf("Release"), 27 to listOf("Ana", "Cinema"))
                Agenda(dayTitle = "WEDNESDAY · 15 NOVEMBER", today = today, nowMinute = 9 * 60 + 41, next = today[2],
                    nextIn = "IN 49 MIN", later = listOf(today[3], today[4]), monthTitle = "NOVEMBER 2026",
                    weekdays = listOf("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"),
                    days = (0 until 35).map { cell ->
                        val n = cell - 5 + 1
                        when {
                            n < 1 -> Day(26 + cell, inMonth = false)
                            n > 30 -> Day(n - 30, inMonth = false)
                            else -> sample[n].orEmpty().let { Day(n, isToday = n == 15, titles = it.take(3), more = max(it.size - 3, 0)) }
                        }
                    })
            }
        }
    }

    /** The phone's photo library, newest first. */
    data class Photos(
        val hasAccess: Boolean = true,
        val count: Int = 0,
        /** The one shown: the widget's slideshow and the centre. */
        val current: Int = 0,
        /** Fullscreen: the gallery's picked photo, the first row shown, and whether it is open. */
        val selected: Int = 0,
        val scrollRow: Int = 0,
        val viewing: Boolean = false,
        /** "12 OCTOBER 2026", for whichever is shown. */
        val caption: String = "",
    ) {
        companion object { val preview = Photos(count = 248, current = 3, selected = 3, caption = "12 OCTOBER 2026") }
    }

    /**
     * The teleprompter reads the note. Scrolling is worked out from when it last changed, so the
     * glasses move it smoothly every frame without anything being sent.
     */
    data class Prompter(
        val isRunning: Boolean = false,
        /** Points a second. */
        val speed: Double = 60.0,
        val anchorOffset: Float = 0f,
        /** System.currentTimeMillis() at the anchor. */
        val anchorTime: Long = 0L,
    ) {
        fun offset(at: Long): Float = if (!isRunning) anchorOffset else anchorOffset + ((at - anchorTime) / 1000.0 * speed).toFloat()
        /** The speed as the phone shows it: 1 to 10. */
        val step: Int get() = Math.round(speed / 30).toInt()
        companion object { const val MIN_SPEED = 30.0; const val MAX_SPEED = 300.0 }
    }
    data class Clock(
        val time: String,
        val meridiem: String? = null,
        val weekday: String,
        val date: String,
        val nextEvent: String? = null,
        val nextEventTime: String? = null,
        /** "07", for the clock app's seconds. */
        val seconds: String = "00",
        /** Hours (0 until 12), minutes and seconds as fractions, for the dial's hands. */
        val hourHand: Double = 0.0,
        val minuteHand: Double = 0.0,
        val secondHand: Double = 0.0,
        /** The rest of today's calendar, earliest first. */
        val agenda: List<Event> = emptyList(),
        val worldClocks: List<WorldClock> = emptyList(),
    ) {
        data class Event(val title: String, val time: String, val end: String? = null, val isNow: Boolean = false)
        data class WorldClock(val city: String, val time: String, val offset: String, val isDay: Boolean)

        companion object {
            val preview = Clock("9:41", null, "WEDNESDAY", "15 NOVEMBER", "Design review", "10:30",
                seconds = "07", hourHand = 9 + 41 / 60.0, minuteHand = 41 + 7 / 60.0, secondHand = 7.0,
                agenda = listOf(
                    Event("Stand-up", "9:30", "9:45", isNow = true),
                    Event("Design review", "10:30", "11:30"),
                    Event("Lunch with Ana", "13:00", "14:00"),
                    Event("Ship the HUD", "17:00", "18:00")),
                worldClocks = listOf(
                    WorldClock("NEW YORK", "7:41", "−2H", true),
                    WorldClock("LONDON", "12:41", "+3H", true),
                    WorldClock("TOKYO", "21:41", "+12H", false)))
        }
    }

    data class Hour(val label: String, val icon: WeatherIcon, val temperature: Int, val precipitation: Int = 0)
    data class Day(val label: String, val icon: WeatherIcon, val high: Int, val low: Int, val precipitation: Int)

    data class Weather(
        val temperature: Int,
        val condition: String,
        val icon: WeatherIcon,
        val high: Int,
        val low: Int,
        val place: String,
        /** The next twelve hours, now first. */
        val hours: List<Hour> = emptyList(),
        val days: List<Day> = emptyList(),
        val feelsLike: Int? = null,
        val humidity: Int? = null,
        val windKmh: Int? = null,
        val sunrise: String? = null,
        val sunset: String? = null,
        val air: Air? = null,
    ) {
        /** Air quality, UV and pollen. */
        data class Air(val index: Int, val label: String, val uv: Double, val uvLabel: String,
                       val pm25: Double? = null, val pollen: String? = null)

        companion object {
            val preview: Weather = run {
                val temps = listOf(12, 12, 13, 14, 14, 13, 12, 11, 10, 10, 9, 9)
                val icons = listOf(WeatherIcon.drizzle, WeatherIcon.drizzle, WeatherIcon.rain, WeatherIcon.cloud,
                    WeatherIcon.partly, WeatherIcon.partly, WeatherIcon.cloud, WeatherIcon.cloud, WeatherIcon.moon,
                    WeatherIcon.moon, WeatherIcon.moon, WeatherIcon.moon)
                val rain = listOf(70, 60, 55, 30, 10, 5, 10, 10, 15, 5, 0, 0)
                Weather(12, "LIGHT RAIN", WeatherIcon.drizzle, 14, 7, "LISBON",
                    hours = (0 until 12).map { Hour(if (it == 0) "NOW" else "${10 + it}", icons[it], temps[it], rain[it]) },
                    days = listOf(
                        Day("TODAY", WeatherIcon.drizzle, 14, 7, 70), Day("THU", WeatherIcon.partly, 16, 8, 10),
                        Day("FRI", WeatherIcon.sun, 19, 10, 0), Day("SAT", WeatherIcon.sun, 20, 11, 0),
                        Day("SUN", WeatherIcon.cloud, 17, 11, 20), Day("MON", WeatherIcon.rain, 13, 9, 90),
                        Day("TUE", WeatherIcon.rain, 12, 6, 60)),
                    feelsLike = 10, humidity = 82, windKmh = 18, sunrise = "7:24", sunset = "17:21",
                    air = Air(24, "FAIR", 2.1, "LOW", 8.2, "GRASS · LOW"))
            }
        }
    }

    /** A moving map. */
    data class Minimap(
        val place: String,
        /** Degrees clockwise from north. */
        val heading: Double,
        val headingLabel: String,
        val speed: String,
        /** Metres across a 470-point panel: the zoom. */
        val spanMetres: Int,
        /** Where the wearer is from the centre of the map raster, metres east and north. */
        val groundOffsetEast: Double = 0.0,
        val groundOffsetNorth: Double = 0.0,
        /** Metres across the current raster. */
        val groundSpanMetres: Double = 0.0,
        /** The route, metres east and north of the raster's centre. */
        val route: List<Offset> = emptyList(),
    ) {
        val pointsPerMetre: Double get() = 470.0 / max(spanMetres, 1)
        val effectiveGroundSpan: Double get() = if (groundSpanMetres > 0) groundSpanMetres else spanMetres * GROUND_OVERSIZE

        companion object {
            /** The raster covers more than the panel shows, so turning it never shows a corner. */
            const val GROUND_OVERSIZE = 1.9
            val preview = Minimap("ALFAMA", 34.0, "NE", "4.2 KM/H", 300)
            val locating = Minimap("LOCATING", 0.0, "", "", 300)
        }
    }

    /** The Maps app: what is searched, what was found, where it is going. */
    data class Maps(
        val query: String = "",
        val isEditing: Boolean = false,
        val results: List<Place> = emptyList(),
        val status: String? = null,
        val navigation: Navigation? = null,
        val driving: Boolean = false,
    ) {
        data class Place(val name: String, val detail: String, val distance: String)
        data class Navigation(
            val destination: String,
            val instruction: String,
            val maneuver: Maneuver,
            val stepDistance: String,
            val remainingTime: String,
            val remainingDistance: String,
            val arrival: String,
            val arrived: Boolean = false,
        )
    }

    enum class Maneuver { straight, left, right, slightLeft, slightRight, uturn, roundabout, arrive }

    enum class TimerState { idle, running, paused, done }

    data class TimerReading(
        val text: String = "5:00",
        val progress: Float? = 0f,
        val state: TimerState = TimerState.idle,
        val isStopwatch: Boolean = false,
    )

    data class Activity(
        val steps: Int,
        val goal: Int = 8000,
        val distanceKm: Double? = null,
        val floors: Int? = null,
        /** Steps in each hour of today so far, midnight first. */
        val hourly: List<Int> = emptyList(),
    ) {
        val fraction: Double get() = min(steps.toDouble() / max(goal, 1), 1.0)

        companion object {
            val preview = Activity(6412, 8000, 4.7, 6, listOf(0, 0, 0, 0, 0, 0, 0, 120, 880, 1240, 310, 460, 920, 1330, 640, 512))
        }
    }

    data class NowPlaying(
        val title: String,
        val artist: String,
        val album: String = "",
        val isPlaying: Boolean,
        val elapsed: Double = 0.0,
        val duration: Double = 0.0,
        /** Which app is playing it, for the phone to say. */
        val app: String = "",
    ) {
        val progress: Float get() = if (duration > 0) min(elapsed / duration, 1.0).toFloat() else 0f

        companion object {
            fun time(seconds: Double): String {
                val s = max(seconds.toInt(), 0)
                return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
            }
            val preview = NowPlaying("Midnight City", "M83", "Hurry Up, We're Dreaming", true, 97.0, 243.0)
        }
    }

    data class Note(val text: String = "", val isEditing: Boolean = false, val scroll: Float = 0f)

    data class Captions(
        val isListening: Boolean = false,
        /** Finished sentences, oldest first; only the last few are kept here. */
        val lines: List<String> = emptyList(),
        /** What is being said right now, still changing. */
        val partial: String = "",
        val status: String = "OFF",
        val elapsed: String = "",
    ) {
        companion object {
            val preview = Captions(true, listOf("So the plan is to ship the HUD on Friday.",
                "We still need the icons for the editor,", "and someone should test it on the train."),
                "I can do that tomorrow morning", "LISTENING · PT-BR", "3:12")
        }
    }

    data class YouTube(
        val hasVideo: Boolean = false,
        val videoId: String = "",
        val title: String = "",
        val channel: String = "",
        val isPlaying: Boolean = false,
        val isLive: Boolean = false,
        val elapsed: Double = 0.0,
        val duration: Double = 0.0,
        val isAd: Boolean = false,
        val canSkipAd: Boolean = false,
        /** Why the video shows no picture, when it shows none. */
        val notice: String = "",
        val page: Page = Page.browse,
        val tab: Tab = Tab.home,
        val showsSubscriptions: Boolean = false,
        val query: String = "",
        val isEditingQuery: Boolean = false,
        val home: List<YouTubeVideo> = emptyList(),
        val subscriptions: List<YouTubeVideo> = emptyList(),
        val results: List<YouTubeVideo> = emptyList(),
        val upNext: List<YouTubeVideo> = emptyList(),
        val queue: List<YouTubeVideo> = emptyList(),
        val scrollRow: Int = 0,
        val loading: Boolean = false,
        val problem: String = "",
    ) {
        enum class Tab(val title: String) { home("HOME"), subscriptions("SUBSCRIPTIONS"), search("SEARCH") }
        enum class Page { browse, player }

        val progress: Float get() = if (duration > 0) min(elapsed / duration, 1.0).toFloat() else 0f
        val tabs: List<Tab> get() = if (showsSubscriptions) Tab.entries else listOf(Tab.home, Tab.search)
        fun list(tab: Tab) = when (tab) { Tab.home -> home; Tab.subscriptions -> subscriptions; Tab.search -> results }
        val sideList: List<YouTubeVideo> get() = queue + upNext.filter { it.id != videoId }

        companion object {
            val preview = YouTube(hasVideo = true, videoId = "preview", title = "Building a heads-up display from scratch",
                channel = "Tech Explained", isPlaying = true, elapsed = 412.0, duration = 1140.0,
                home = YouTubeVideo.samples, results = YouTubeVideo.samples.reversed(),
                upNext = YouTubeVideo.samples.drop(3), queue = YouTubeVideo.samples.take(2))
        }
    }

    /** The sky over the wearer: the day's sun and moon for the widget, the stars for the app. */
    data class Sky(
        val hasLocation: Boolean = false,
        val sunrise: String? = null,
        val sunset: String? = null,
        val goldenHour: String? = null,
        /** 0 at sunrise and 1 at sunset; null at night. */
        val dayProgress: Double? = null,
        val sunAltitude: Double = 0.0,
        val moonPhase: String = "",
        val moonPhaseIndex: Int = 0,
        val moonIllumination: Int = 0,
        val moonrise: String? = null,
        val moonset: String? = null,
        val stars: List<Star> = emptyList(),
        val lines: List<Figure> = emptyList(),
        val constellations: List<Label> = emptyList(),
        val starNames: List<Label> = emptyList(),
        val bodies: List<Body> = emptyList(),
        val milkyWay: List<Band> = emptyList(),
        val ecliptic: List<Point> = emptyList(),
        val signs: List<Sign> = emptyList(),
        val sunSign: Zodiac? = null,
        val moonSign: Zodiac? = null,
    ) {
        data class Point(val az: Float, val alt: Float)
        data class Star(val az: Float, val alt: Float, val mag: Float, val bv: Float)
        data class Label(val az: Float, val alt: Float, val name: String, val zodiac: Boolean = false)
        data class Figure(val points: List<Point>, val zodiac: Boolean = false)
        data class Band(val level: Int, val points: List<Point>)
        data class Sign(val sign: Zodiac, val az: Float, val alt: Float)
        data class Body(val kind: Kind, val name: String, val az: Double, val alt: Double, val mag: Double) {
            enum class Kind { sun, moon, planet }
        }
    }

    /** Aircraft and the space station over the wearer. */
    data class Overhead(val planes: List<Plane> = emptyList(), val station: Station? = null, val status: String = "") {
        data class Point(val az: Double, val alt: Double)
        data class Plane(
            val id: String, val callsign: String, val airline: String?, val model: String?,
            val altitude: Double, val speed: Double, val distance: Double, val track: Double,
            val position: Point, val ahead: Point, val trail: List<Point>,
        )
        data class Station(val position: Point, val altitude: Double, val speed: Double, val distance: Double,
                           val sunlit: Boolean, val path: List<Point>)
    }

    /** The Mac streamed by HudCast. */
    data class Desktop(
        val status: String = "LOOKING FOR YOUR MAC",
        val connected: Boolean = false,
        val hasPicture: Boolean = false,
        val host: String = "",
        val windows: List<DesktopWindow> = emptyList(),
        val source: DesktopSource? = null,
    ) {
        val aspect: Float get() = source?.takeIf { it.height > 0 }?.let { it.width.toFloat() / it.height } ?: (16f / 10f)
        val activeWindow: Int? get() = source?.window?.let { id -> windows.indexOfFirst { it.id == id }.takeIf { it >= 0 } }
    }

    data class Browser(
        val url: String = "",
        val title: String = "",
        val tabs: List<String> = listOf("New Tab"),
        val activeTab: Int = 0,
        val canGoBack: Boolean = false,
        val canGoForward: Boolean = false,
        val loading: Float? = null,
        val isEditingAddress: Boolean = false,
        val isFullscreen: Boolean = false,
        val isHome: Boolean = true,
        val isFavorite: Boolean = false,
    )

    companion object {
        /** What the device starts from: the time, and nothing it has not been told. */
        val blank = HudSnapshot(weather = null, minimap = Minimap.locating, activity = null, music = null,
            agenda = Agenda(), photos = Photos(),
            captions = Captions(), youtube = YouTube())
    }
}

enum class WeatherIcon { sun, moon, partly, partlyNight, cloud, fog, drizzle, rain, heavyRain, snow, storm }

/** One video, as a list shows it. */
@Serializable
data class YouTubeVideo(
    val id: String,
    val title: String,
    val channel: String = "",
    /** "11:07", "LIVE", or empty. */
    val duration: String = "",
    /** "2.2K views · 3 days ago", as YouTube words it. */
    val meta: String = "",
) {
    val isLive get() = duration.uppercase() == "LIVE"
    val thumbnail get() = "https://i.ytimg.com/vi/$id/mqdefault.jpg"

    companion object {
        val samples = listOf(
            YouTubeVideo("s1", "Night drive through Tokyo, no talking", "City Walks", "1:12:40", "2.1M views · 3 weeks ago"),
            YouTubeVideo("s2", "How birdbath optics work", "Optics Lab", "14:22", "380K views · 5 days ago"),
            YouTubeVideo("s3", "Lisbon trams, a whole day", "Slow TV", "LIVE", "1.2K watching"),
            YouTubeVideo("s4", "Making bread with one bowl", "Kitchen Notes", "9:05", "90K views · 1 day ago"),
            YouTubeVideo("s5", "The quietest place on Earth", "Field Recordings", "22:31", "4.4M views · 2 years ago"),
            YouTubeVideo("s6", "Jazz for a rainy afternoon", "Hygge Café", "3:38:14", "728 views · 12 hours ago"),
            YouTubeVideo("s7", "Fixing a 1970s synthesizer", "Bench Repairs", "41:10", "212K views · 1 month ago"),
            YouTubeVideo("s8", "Starship catch, every angle", "Launch Pad", "11:07", "657K views · 19 hours ago"),
            YouTubeVideo("s9", "A walk in the Alfama at dawn", "City Walks", "58:02", "41K views · 6 days ago"),
        )
    }
}

/** A window on the Mac that can be streamed on its own. */
@Serializable
data class DesktopWindow(val id: Long, val app: String, val title: String) {
    val label get() = if (title.isEmpty() || title == app) app else "$app — $title"
}

/** What the Mac is streaming. */
@Serializable
data class DesktopSource(val window: Long? = null, val width: Int, val height: Int, val host: String)

/**
 * The clock app's timer: counts down from a set time, or up as a stopwatch. Kept as a start time
 * plus what ran before, so it stays right however irregular the ticks that read it are.
 */
data class HudTimer(
    val setSeconds: Int = 300,
    private val startedAt: Long? = null,
    private val banked: Long = 0,
) {
    val isRunning get() = startedAt != null
    val isIdle get() = startedAt == null && banked == 0L

    fun elapsedMs(now: Long) = banked + (startedAt?.let { now - it } ?: 0)
    fun isDone(now: Long) = setSeconds > 0 && elapsedMs(now) >= setSeconds * 1000L

    fun toggle(now: Long): HudTimer = when {
        isDone(now) -> copy(startedAt = now, banked = 0)
        startedAt != null -> copy(startedAt = null, banked = banked + (now - startedAt))
        else -> copy(startedAt = now)
    }

    fun reset() = copy(startedAt = null, banked = 0)
    fun set(minutes: Int) = HudTimer(setSeconds = minutes.coerceIn(0, 180) * 60)
    fun add(minutes: Int) = if (setSeconds == 0) this else copy(setSeconds = min(setSeconds + minutes * 60, 180 * 60))

    /** The wheel over the idle timer: a minute a notch, up for more. */
    fun adjust(notches: Int): HudTimer {
        if (!isIdle) return this
        return HudTimer(setSeconds = (setSeconds + notches * 60).coerceIn(0, 180 * 60))
    }

    fun reading(now: Long): HudSnapshot.TimerReading {
        val elapsed = elapsedMs(now) / 1000.0
        val stopwatch = setSeconds == 0
        val text: String
        val progress: Float?
        if (stopwatch) {
            text = format(elapsed); progress = null
        } else {
            text = format(ceil(max(setSeconds - elapsed, 0.0)))
            progress = min(elapsed / setSeconds, 1.0).toFloat()
        }
        val state = when {
            isDone(now) -> HudSnapshot.TimerState.done
            isRunning -> HudSnapshot.TimerState.running
            isIdle -> HudSnapshot.TimerState.idle
            else -> HudSnapshot.TimerState.paused
        }
        return HudSnapshot.TimerReading(text, progress, state, stopwatch)
    }

    companion object {
        fun format(seconds: Double): String {
            val s = max(seconds.toInt(), 0)
            return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60)
            else "%d:%02d".format(s / 60, s % 60)
        }
    }
}

/** The cursor on the canvas, moved by the touchpad, kept inside the glasses. */
data class Pointer(val position: Offset = Offset(960f, 540f)) {
    fun moved(dx: Float, dy: Float) = Pointer(Offset(
        (position.x + dx).coerceIn(0f, HudTheme.CANVAS_WIDTH - 1),
        (position.y + dy).coerceIn(0f, HudTheme.CANVAS_HEIGHT - 1)))

    companion object {
        /** Touchpad pixels to canvas points: the cover screen is small, the canvas wide. */
        fun scale(dx: Int) = dx * 1.6f
    }
}
