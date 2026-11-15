package com.thehud.data

import android.annotation.SuppressLint
import android.content.Context
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import com.thehud.core.HudSnapshot
import com.thehud.core.WeatherIcon
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import kotlin.math.roundToInt

/** Open-Meteo, as on the iPhone: no key, and nothing sent but the coordinates. */
object OpenMeteo {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun weather(lat: Double, lon: Double, place: String): HudSnapshot.Weather? = withContext(Dispatchers.IO) {
        val url = "https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f".format(Locale.US, lat, lon) +
            "&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,is_day" +
            "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=2"
        runCatching {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.setRequestProperty("User-Agent", "TheHud")
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            decode(body, place)
        }.getOrNull()
    }

    fun decode(body: String, place: String): HudSnapshot.Weather {
        val r = json.decodeFromString(Response.serializer(), body)
        val now = r.current.time.take(13)
        val hourly = r.hourly
        val start = hourly?.time?.indexOfFirst { it.take(13) >= now }?.coerceAtLeast(0) ?: 0
        val hours = hourly?.let { h ->
            (start until minOf(start + 4, h.time.size)).map { i ->
                HudSnapshot.Hour(if (i == start) "NOW" else h.time[i].substring(11, 13),
                                 icon(h.weather_code[i], (h.is_day?.getOrNull(i) ?: 1) == 1),
                                 h.temperature_2m[i].roundToInt())
            }
        } ?: emptyList()
        return HudSnapshot.Weather(
            temperature = r.current.temperature_2m.roundToInt(),
            condition = label(r.current.weather_code),
            icon = icon(r.current.weather_code, (r.current.is_day ?: 1) == 1),
            high = r.daily.temperature_2m_max.firstOrNull()?.roundToInt() ?: 0,
            low = r.daily.temperature_2m_min.firstOrNull()?.roundToInt() ?: 0,
            place = place.uppercase(),
            hours = hours,
        )
    }

    fun label(code: Int) = when (code) {
        0 -> "CLEAR"; 1 -> "MAINLY CLEAR"; 2 -> "PARTLY CLOUDY"; 3 -> "OVERCAST"
        45, 48 -> "FOG"; 51, 53, 55 -> "DRIZZLE"; 61 -> "LIGHT RAIN"; 63 -> "RAIN"; 65 -> "HEAVY RAIN"
        71, 73, 75 -> "SNOW"; 80, 82 -> "SHOWERS"; 95 -> "THUNDERSTORM"; 99 -> "HAIL"
        else -> "—"
    }

    fun icon(code: Int, day: Boolean) = when (code) {
        0, 1 -> if (day) WeatherIcon.sun else WeatherIcon.moon
        2 -> WeatherIcon.partly
        3 -> WeatherIcon.cloud
        45, 48 -> WeatherIcon.fog
        51, 53, 55 -> WeatherIcon.drizzle
        61, 63, 65, 80, 82 -> WeatherIcon.rain
        71, 73, 75 -> WeatherIcon.snow
        95, 99 -> WeatherIcon.storm
        else -> WeatherIcon.cloud
    }

    @Serializable private data class Current(val time: String, val temperature_2m: Double, val weather_code: Int, val is_day: Int? = null)
    @Serializable private data class Hourly(val time: List<String>, val temperature_2m: List<Double>, val weather_code: List<Int>, val is_day: List<Int>? = null)
    @Serializable private data class Daily(val temperature_2m_max: List<Double>, val temperature_2m_min: List<Double>)
    @Serializable private data class Response(val current: Current, val hourly: Hourly? = null, val daily: Daily)
}

/** Where the phone is, coarsely: enough for the weather and the place name. */
class Whereabouts(private val context: Context) {
    @SuppressLint("MissingPermission")
    fun last(): Location? {
        val manager = context.getSystemService(LocationManager::class.java) ?: return null
        return runCatching {
            listOf(LocationManager.FUSED_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
                .mapNotNull { if (manager.isProviderEnabled(it)) manager.getLastKnownLocation(it) else null }
                .maxByOrNull { it.time }
        }.getOrNull()
    }

    @Suppress("DEPRECATION")
    suspend fun placeName(location: Location): String = withContext(Dispatchers.IO) {
        runCatching {
            val a = Geocoder(context).getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull()
            a?.locality ?: a?.subAdminArea ?: a?.adminArea
        }.getOrNull() ?: ""
    }
}
