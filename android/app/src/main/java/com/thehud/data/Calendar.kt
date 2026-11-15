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
    private class Instance(val title: String, val begin: Long, val end: Long, val allDay: Boolean)

    val allowed get() = context.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    private fun instances(from: Long, to: Long): List<Instance> {
        if (!allowed) return emptyList()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from); ContentUris.appendId(it, to)
        }.build()
        val columns = arrayOf(CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY)
        return runCatching {
            context.contentResolver.query(uri, columns, null, null, CalendarContract.Instances.BEGIN + " ASC")?.use { c ->
                buildList {
                    while (c.moveToNext()) add(Instance(c.getString(0) ?: "", c.getLong(1), c.getLong(2), c.getInt(3) == 1))
                }
            } ?: emptyList()
        }.getOrDefault(emptyList())
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
