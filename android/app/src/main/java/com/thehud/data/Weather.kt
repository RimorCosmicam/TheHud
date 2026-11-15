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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import kotlin.math.roundToInt

/** A GET that returns the body, or null. Every provider here is a small JSON service. */
internal fun httpGet(url: String, headers: Map<String, String> = emptyMap(), timeout: Int = 12_000): String? = runCatching {
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.setRequestProperty("User-Agent", "TheHud")
    headers.forEach { (k, v) -> connection.setRequestProperty(k, v) }
    connection.connectTimeout = timeout
    connection.readTimeout = timeout
    if (connection.responseCode !in 200..299) return@runCatching null
    connection.inputStream.bufferedReader().use { it.readText() }
}.getOrNull()

/** Open-Meteo, as on the iPhone: no key, and nothing sent but the coordinates, rounded. */
object OpenMeteo {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun weather(lat: Double, lon: Double, place: String, is24: Boolean = true): HudSnapshot.Weather? = withContext(Dispatchers.IO) {
        val url = "https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f".format(Locale.US, lat, lon) +
            "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day" +
            "&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset" +
            "&timezone=auto&forecast_days=7"
        val body = httpGet(url) ?: return@withContext null
        val weather = runCatching { decode(body, place, is24) }.getOrNull() ?: return@withContext null
        weather.copy(air = air(lat, lon))
    }

    fun decode(body: String, place: String, is24: Boolean = true): HudSnapshot.Weather {
        val r = json.decodeFromString(Response.serializer(), body)
        val parse = SimpleDateFormat("yyyy-MM-dd'T'HH:mm", Locale.US)
        val dayParse = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val hourLabel = SimpleDateFormat(if (is24) "HH" else "ha", Locale.US)
        val clockLabel = SimpleDateFormat(if (is24) "H:mm" else "h:mm", Locale.US)
        val dayLabel = SimpleDateFormat("EEE", Locale.getDefault())
        val now = r.current.time.take(13)
        val hours = r.hourly?.let { h ->
            val start = h.time.indexOfFirst { it.take(13) >= now }.coerceAtLeast(0)
            (start until minOf(start + 12, h.time.size)).map { i ->
                HudSnapshot.Hour(
                    if (i == start) "NOW" else runCatching { hourLabel.format(parse.parse(h.time[i])!!).uppercase() }.getOrDefault(""),
                    icon(h.weather_code[i], (h.is_day?.getOrNull(i) ?: 1) == 1),
                    h.temperature_2m[i].roundToInt(),
                    h.precipitation_probability?.getOrNull(i) ?: 0)
            }
        } ?: emptyList()
        val d = r.daily
        val days = d.time.indices.map { i ->
            HudSnapshot.Day(
                if (i == 0) "TODAY" else runCatching { dayLabel.format(dayParse.parse(d.time[i])!!).uppercase().trimEnd('.') }.getOrDefault(""),
                icon(d.weather_code?.getOrNull(i) ?: -1, true),
                d.temperature_2m_max[i].roundToInt(), d.temperature_2m_min[i].roundToInt(),
                d.precipitation_probability_max?.getOrNull(i) ?: 0)
        }
        fun clock(s: String?) = s?.let { runCatching { clockLabel.format(parse.parse(it)!!) }.getOrNull() }
        return HudSnapshot.Weather(
            temperature = r.current.temperature_2m.roundToInt(),
            condition = label(r.current.weather_code),
            icon = icon(r.current.weather_code, (r.current.is_day ?: 1) == 1),
            high = d.temperature_2m_max.firstOrNull()?.roundToInt() ?: 0,
            low = d.temperature_2m_min.firstOrNull()?.roundToInt() ?: 0,
            place = place.uppercase(),
            hours = hours, days = days,
            feelsLike = r.current.apparent_temperature?.roundToInt(),
            humidity = r.current.relative_humidity_2m?.roundToInt(),
            windKmh = r.current.wind_speed_10m?.roundToInt(),
            sunrise = clock(d.sunrise?.firstOrNull()),
            sunset = clock(d.sunset?.firstOrNull()),
        )
    }

    // ------------------------------------------------------------------ air

    private val pollenKeys = listOf("alder_pollen", "birch_pollen", "grass_pollen", "mugwort_pollen", "olive_pollen", "ragweed_pollen")

    /** Air quality, UV and pollen, from the same provider and on the same terms. */
    fun air(lat: Double, lon: Double): HudSnapshot.Weather.Air? {
        val url = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=%.2f&longitude=%.2f".format(Locale.US, lat, lon) +
            "&current=european_aqi,pm2_5,uv_index," + pollenKeys.joinToString(",") + "&timezone=auto"
        val body = httpGet(url) ?: return null
        return runCatching { decodeAir(body) }.getOrNull()
    }

    fun decodeAir(body: String): HudSnapshot.Weather.Air {
        val current = (json.parseToJsonElement(body) as JsonObject)["current"] as JsonObject
        fun value(key: String) = runCatching { current[key]?.jsonPrimitive?.doubleOrNull }.getOrNull()
        val index = (value("european_aqi") ?: 0.0).roundToInt()
        val uv = value("uv_index") ?: 0.0
        // Pollen is only measured in Europe; elsewhere it is missing, and so is the line.
        val pollen = pollenKeys.mapNotNull { k -> value(k)?.let { k to it } }.maxByOrNull { it.second }
            ?.let { (k, grains) -> k.removeSuffix("_pollen").uppercase() + " · " + pollenLevel(grains) }
        return HudSnapshot.Weather.Air(index, aqiLabel(index), uv, uvLabel(uv), value("pm2_5"), pollen)
    }

    fun aqiLabel(i: Int) = when {
        i < 20 -> "GOOD"; i < 40 -> "FAIR"; i < 60 -> "MODERATE"; i < 80 -> "POOR"; i < 100 -> "VERY POOR"; else -> "EXTREMELY POOR"
    }
    fun uvLabel(uv: Double) = when {
        uv < 3 -> "LOW"; uv < 6 -> "MODERATE"; uv < 8 -> "HIGH"; uv < 11 -> "VERY HIGH"; else -> "EXTREME"
    }
    private fun pollenLevel(g: Double) = when { g < 1 -> "NONE"; g < 20 -> "LOW"; g < 100 -> "MODERATE"; else -> "HIGH" }

    fun label(code: Int) = when (code) {
        0 -> "CLEAR"; 1 -> "MAINLY CLEAR"; 2 -> "PARTLY CLOUDY"; 3 -> "OVERCAST"
        45, 48 -> "FOG"; 51, 53, 55 -> "DRIZZLE"; 56, 57 -> "FREEZING DRIZZLE"; 61 -> "LIGHT RAIN"; 63 -> "RAIN"; 65 -> "HEAVY RAIN"
        66, 67 -> "FREEZING RAIN"; 71, 73, 75, 77 -> "SNOW"; 80, 81, 82 -> "SHOWERS"; 85, 86 -> "SNOW SHOWERS"
        95 -> "THUNDERSTORM"; 96, 99 -> "HAIL"
        else -> "—"
    }

    fun icon(code: Int, day: Boolean) = when (code) {
        0, 1 -> if (day) WeatherIcon.sun else WeatherIcon.moon
        2 -> if (day) WeatherIcon.partly else WeatherIcon.partlyNight
        3 -> WeatherIcon.cloud
        45, 48 -> WeatherIcon.fog
        51, 53, 55, 56, 57 -> WeatherIcon.drizzle
        61, 63, 80, 81 -> WeatherIcon.rain
        65, 66, 67, 82 -> WeatherIcon.heavyRain
        71, 73, 75, 77, 85, 86 -> WeatherIcon.snow
        95, 96, 99 -> WeatherIcon.storm
        else -> WeatherIcon.cloud
    }

    @Serializable private data class Current(
        val time: String, val temperature_2m: Double, val weather_code: Int, val is_day: Int? = null,
        val apparent_temperature: Double? = null, val relative_humidity_2m: Double? = null, val wind_speed_10m: Double? = null)
    @Serializable private data class Hourly(val time: List<String>, val temperature_2m: List<Double>, val weather_code: List<Int>,
                                            val is_day: List<Int>? = null, val precipitation_probability: List<Int?>? = null)
    @Serializable private data class Daily(
        val time: List<String> = emptyList(), val weather_code: List<Int>? = null,
        val temperature_2m_max: List<Double>, val temperature_2m_min: List<Double>,
        val precipitation_probability_max: List<Int?>? = null, val sunrise: List<String>? = null, val sunset: List<String>? = null)
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

    /** A fresh coarse fix, when nothing recent is cached (after a restart, say). */
    @SuppressLint("MissingPermission")
    suspend fun current(): Location? {
        val manager = context.getSystemService(LocationManager::class.java) ?: return null
        val provider = listOf(LocationManager.FUSED_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            .firstOrNull { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) } ?: return null
        return kotlinx.coroutines.withTimeoutOrNull(20_000L) {
            kotlinx.coroutines.suspendCancellableCoroutine { done ->
                runCatching {
                    manager.getCurrentLocation(provider, null, context.mainExecutor) { done.resume(it) { } }
                }.onFailure { done.resume(null) { } }
            }
        }
    }

    @Suppress("DEPRECATION")
    suspend fun placeName(location: Location, fine: Boolean = false): String = withContext(Dispatchers.IO) {
        runCatching {
            val a = Geocoder(context).getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull()
            if (fine) a?.subLocality ?: a?.locality ?: a?.featureName else a?.locality ?: a?.subAdminArea ?: a?.adminArea
        }.getOrNull() ?: ""
    }
}
