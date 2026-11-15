package com.thehud.core

import androidx.compose.ui.geometry.Offset
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Everything the glasses draw, in one value: the glasses are a picture of this. */
data class HudSnapshot(
    val clock: Clock = Clock.preview,
    val weather: Weather? = Weather.preview,
    val note: Note = Note(),
    val timer: TimerReading = TimerReading(),
    val browser: Browser = Browser(),
    /** Where the pointer is, in canvas points. Null hides it. */
    val cursor: Offset? = null,
) {
    data class Clock(
        val time: String,
        val meridiem: String? = null,
        val weekday: String,
        val date: String,
        val nextEvent: String? = null,
        val nextEventTime: String? = null,
    ) {
        companion object {
            val preview = Clock("9:41", null, "WEDNESDAY", "15 NOVEMBER", "Design review", "10:30")
        }
    }

    data class Hour(val label: String, val icon: WeatherIcon, val temperature: Int)

    data class Weather(
        val temperature: Int,
        val condition: String,
        val icon: WeatherIcon,
        val high: Int,
        val low: Int,
        val place: String,
        val hours: List<Hour> = emptyList(),
    ) {
        companion object {
            val preview = Weather(12, "LIGHT RAIN", WeatherIcon.rain, 14, 7, "LISBON", listOf(
                Hour("11", WeatherIcon.rain, 12), Hour("12", WeatherIcon.rain, 13),
                Hour("13", WeatherIcon.cloud, 14), Hour("14", WeatherIcon.partly, 14)))
        }
    }

    data class Note(val text: String = "", val isEditing: Boolean = false, val scroll: Float = 0f)

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
    )

    enum class TimerState { idle, running, paused, done }

    data class TimerReading(
        val text: String = "5:00",
        val progress: Float? = 0f,
        val state: TimerState = TimerState.idle,
        val isStopwatch: Boolean = false,
    )
}

enum class WeatherIcon { sun, moon, partly, cloud, fog, drizzle, rain, snow, storm }

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
