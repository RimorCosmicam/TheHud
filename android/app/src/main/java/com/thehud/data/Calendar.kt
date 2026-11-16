package com.thehud.data

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import com.thehud.core.HudSnapshot
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs

/** The calendar on the phone: the next thing, and the rest of today. Nothing without permission. */
class CalendarProvider(private val context: Context) {
    private class Instance(val title: String, val begin: Long, val end: Long, val allDay: Boolean,
                           val calendarId: Long = 0, val location: String = "")

    val allowed get() = context.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    private fun instances(from: Long, to: Long): List<Instance> {
        if (!allowed) return emptyList()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from); ContentUris.appendId(it, to)
        }.build()
        val columns = arrayOf(CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.EVENT_LOCATION)
        return runCatching {
            context.contentResolver.query(uri, columns, null, null, CalendarContract.Instances.BEGIN + " ASC")?.use { c ->
                buildList {
                    while (c.moveToNext()) {
                        val allDay = c.getInt(3) == 1
                        // All-day events are stored as UTC midnights: they are the same dates here.
                        val begin = if (allDay) localMidnight(c.getLong(1)) else c.getLong(1)
                        val end = if (allDay) localMidnight(c.getLong(2)) else c.getLong(2)
                        add(Instance(c.getString(0) ?: "", begin, end, allDay, c.getLong(4), c.getString(5) ?: ""))
                    }
                }
            } ?: emptyList()
        }.getOrDefault(emptyList())
    }

    private fun localMidnight(utc: Long): Long {
        val u = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = utc }
        return Calendar.getInstance().apply {
            clear(); set(u.get(Calendar.YEAR), u.get(Calendar.MONTH), u.get(Calendar.DAY_OF_MONTH))
        }.timeInMillis
    }

    /** The calendar app: today as a timeline, what is next, and the month around it. As the iPhone's. */
    fun agendaApp(now: Long = System.currentTimeMillis(), is24: Boolean = true): HudSnapshot.Agenda {
        val locale = Locale.getDefault()
        fun local(skeleton: String, at: Long) =
            SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(locale, skeleton), locale).format(Date(at))
        val time = SimpleDateFormat(if (is24) "H:mm" else "h:mm", Locale.US)
        val at = Calendar.getInstance().apply { timeInMillis = now }
        val nowMinute = at.get(Calendar.HOUR_OF_DAY) * 60 + at.get(Calendar.MINUTE)
        val dayTitle = (local("EEEE", now) + " \u00B7 " + local("d MMMM", now)).uppercase()
        val monthTitle = local("MMMM yyyy", now).uppercase()
        // Weeks as the phone's calendar starts them.
        val first = at.firstDayOfWeek
        val symbols = java.text.DateFormatSymbols(Locale.US).shortWeekdays
        val weekdays = (0 until 7).map { symbols[(first - 1 + it) % 7 + 1].uppercase() }

        fun startOfDay(t: Long) = Calendar.getInstance().apply {
            timeInMillis = t; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        fun plusDays(t: Long, days: Int) = Calendar.getInstance().apply { timeInMillis = t; add(Calendar.DAY_OF_MONTH, days) }.timeInMillis
        val dayStart = startOfDay(now).timeInMillis
        val dayEnd = plusDays(dayStart, 1)
        val monthStart = startOfDay(now).apply { set(Calendar.DAY_OF_MONTH, 1) }
        val gridStart = plusDays(monthStart.timeInMillis, -((monthStart.get(Calendar.DAY_OF_WEEK) - first + 7) % 7))
        val monthEnd = Calendar.getInstance().apply { timeInMillis = monthStart.timeInMillis; add(Calendar.MONTH, 1) }.timeInMillis

        val base = HudSnapshot.Agenda(dayTitle = dayTitle, nowMinute = nowMinute, monthTitle = monthTitle, weekdays = weekdays)
        if (!allowed) return base.copy(hasAccess = false, days = monthDays(gridStart, monthStart.timeInMillis, monthEnd, dayStart, emptyList()))

        // A day either side: all-day events are found by their UTC dates.
        val events = instances(plusDays(gridStart, -1), plusDays(gridStart, 43))
        val tints = HashMap<Long, Int>()
        fun tint(e: Instance) = tints.getOrPut(e.calendarId) { tints.size }
        fun minute(t: Long): Int = when {
            t <= dayStart -> 0
            t >= dayEnd -> 24 * 60
            else -> Calendar.getInstance().apply { timeInMillis = t }.let { it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE) }
        }
        val today = events.filter { it.begin < dayEnd && it.end > dayStart }
            .sortedWith(compareBy({ if (it.allDay) 0 else 1 }, { it.begin }))
        val entries = today.map { e ->
            HudSnapshot.Agenda.Entry(e.title, if (e.allDay) "ALL DAY" else time.format(Date(e.begin)),
                if (e.allDay) "" else time.format(Date(e.end)), if (e.allDay) 0 else minute(e.begin),
                if (e.allDay) 24 * 60 else minute(e.end), e.allDay, e.location, tint(e))
        }
        val timed = today.zip(entries).filter { (e, _) -> !e.allDay && e.end > now }
        var next: HudSnapshot.Agenda.Entry? = null
        var nextIn = ""
        var later = emptyList<HudSnapshot.Agenda.Entry>()
        timed.firstOrNull()?.let { (e, entry) ->
            next = entry
            nextIn = if (e.begin <= now) "NOW" else {
                val minutes = ((e.begin - now) / 60_000).toInt()
                when {
                    minutes < 60 -> "IN ${maxOf(minutes, 1)} MIN"
                    minutes < 180 -> "IN ${minutes / 60} H ${minutes % 60} MIN"
                    else -> "AT ${entry.time}"
                }
            }
            later = timed.drop(1).take(3).map { it.second }
        }
        return base.copy(today = entries, next = next, nextIn = nextIn, later = later,
            days = monthDays(gridStart, monthStart.timeInMillis, monthEnd, dayStart, events))
    }

    /** Whole weeks covering the month, each day with its first few events. */
    private fun monthDays(gridStart: Long, monthStart: Long, monthEnd: Long, today: Long, events: List<Instance>): List<HudSnapshot.Agenda.Day> {
        val days = ArrayList<HudSnapshot.Agenda.Day>()
        val day = Calendar.getInstance().apply { timeInMillis = gridStart }
        while (days.size < 42) {
            val start = day.timeInMillis
            val next = Calendar.getInstance().apply { timeInMillis = start; add(Calendar.DAY_OF_MONTH, 1) }.timeInMillis
            val titles = events.filter { it.begin < next && it.end > start }
                .sortedWith(compareBy({ if (it.allDay) 0 else 1 }, { it.begin })).map { it.title }
            days += HudSnapshot.Agenda.Day(day.get(Calendar.DAY_OF_MONTH), start in monthStart until monthEnd, start == today,
                titles.take(3), maxOf(titles.size - 3, 0))
            // Stop at the end of the week the month ends in: 35 days, or 42.
            if (start >= monthEnd && days.size % 7 == 0) break
            day.timeInMillis = next
        }
        return days
    }

    /** The next event starting within twelve hours, all-day ones left out: they are not about to happen. */
    fun nextEvent(now: Long = System.currentTimeMillis(), is24: Boolean = true): Pair<String, String>? {
        val next = instances(now, now + 12 * 3600_000L).filter { !it.allDay && it.begin > now }.minByOrNull { it.begin } ?: return null
        return next.title to SimpleDateFormat(if (is24) "H:mm" else "h:mm", Locale.US).format(Date(next.begin))
    }

    /** What is left of today: all-day things first, then what is on now and still to come. */
    fun agenda(now: Long = System.currentTimeMillis(), is24: Boolean = true, limit: Int = 6): List<HudSnapshot.Clock.Event> {
        val start = Calendar.getInstance().apply {
            timeInMillis = now; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val f = SimpleDateFormat(if (is24) "H:mm" else "h:mm", Locale.US)
        return instances(start, start + 24 * 3600_000L)
            .filter { it.end > now }
            .sortedWith(compareBy({ if (it.allDay) 0 else 1 }, { it.begin }))
            .take(limit)
            .map { e ->
                HudSnapshot.Clock.Event(e.title, if (e.allDay) "ALL DAY" else f.format(Date(e.begin)),
                    if (e.allDay) null else f.format(Date(e.end)), !e.allDay && e.begin <= now)
            }
    }
}

/** The clock's other places: a fixed three, the useful ones for most people. */
object WorldClocks {
    private val cities = listOf("NEW YORK" to "America/New_York", "LONDON" to "Europe/London", "TOKYO" to "Asia/Tokyo")

    fun now(at: Date = Date(), is24: Boolean = true, here: TimeZone = TimeZone.getDefault()) = cities.map { (city, id) ->
        val zone = TimeZone.getTimeZone(id)
        val f = SimpleDateFormat(if (is24) "H:mm" else "h:mm a", Locale.US).apply { timeZone = zone }
        val hours = (zone.getOffset(at.time) - here.getOffset(at.time)) / 3600_000.0
        val magnitude = abs(hours)
        val amount = if (magnitude == Math.rint(magnitude)) magnitude.toInt().toString() else "%.1f".format(Locale.US, magnitude)
        val hour = Calendar.getInstance(zone).apply { time = at }.get(Calendar.HOUR_OF_DAY)
        HudSnapshot.Clock.WorldClock(city, f.format(at),
            if (hours == 0.0) "SAME TIME" else (if (hours < 0) "−" else "+") + amount + "H", hour in 7 until 19)
    }
}
