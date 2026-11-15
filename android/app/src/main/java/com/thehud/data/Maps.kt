package com.thehud.data

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import com.thehud.core.HudSnapshot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.tan

data class LatLon(val lat: Double, val lon: Double) {
    fun metres(to: LatLon): Double {
        val out = FloatArray(1)
        Location.distanceBetween(lat, lon, to.lat, to.lon, out)
        return out[0].toDouble()
    }
}

/**
 * Where the wearer is, which way the phone faces, and how fast they move. Heading rather than
 * course, as on the iPhone: standing still, a course of nought would snap the map north.
 */
class LocationProvider(private val context: Context, private val onUpdate: (HudSnapshot.Minimap, LatLon, Location) -> Unit) :
    SensorEventListener {
    private var started = false
    private var location: Location? = null
    private var place = ""
    private var lastGeocode = 0L
    private var heading = 0.0
    private var hasHeading = false
    private var lastPublish = 0L
    private val rotation = FloatArray(9)
    private val orientation = FloatArray(3)

    /** The latest heading, unwrapped, for the sky and the map. */
    val facing get() = ((heading % 360) + 360) % 360
    val coordinate get() = location?.let { LatLon(it.latitude, it.longitude) }

    private val listener = LocationListener { l -> location = l; geocode(l); publish() }

    @SuppressLint("MissingPermission")
    fun start() {
        if (started) return
        val manager = context.getSystemService(LocationManager::class.java) ?: return
        started = runCatching {
            // Every fix, as accurately as the phone can: the map slides with each one.
            for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.FUSED_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                if (manager.isProviderEnabled(p)) manager.requestLocationUpdates(p, 1000L, 0f, listener, Looper.getMainLooper())
            }
            true
        }.getOrDefault(false)
        context.getSystemService(SensorManager::class.java)?.let { s ->
            s.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)?.let { s.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
        }
        Whereabouts(context).last()?.let { location = it; geocode(it); publish() }
    }

    fun stop() {
        if (!started) return
        started = false
        context.getSystemService(LocationManager::class.java)?.removeUpdates(listener)
        context.getSystemService(SensorManager::class.java)?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        SensorManager.getRotationMatrixFromVector(rotation, event.values)
        SensorManager.getOrientation(rotation, orientation)
        var degrees = Math.toDegrees(orientation[0].toDouble())
        location?.let { degrees += GeomagneticField(it.latitude.toFloat(), it.longitude.toFloat(), it.altitude.toFloat(), it.time).declination }
        setHeading(((degrees % 360) + 360) % 360)
        val now = System.currentTimeMillis()
        if (now - lastPublish > 100) publish()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /** Unwrapped: 359 to 1 is +2, so the map turns two degrees instead of spinning round. */
    private fun setHeading(degrees: Double) {
        if (!hasHeading) { heading = degrees; hasHeading = true; return }
        val current = ((heading % 360) + 360) % 360
        var delta = degrees - current
        if (delta > 180) delta -= 360
        if (delta < -180) delta += 360
        // A little smoothing: the rotation vector shivers in the hand.
        heading += delta * 0.35
    }

    private fun geocode(l: Location) {
        val now = System.currentTimeMillis()
        if (now - lastGeocode < 60_000) return
        lastGeocode = now
        Thread {
            @Suppress("DEPRECATION")
            val a = runCatching { android.location.Geocoder(context).getFromLocation(l.latitude, l.longitude, 1)?.firstOrNull() }.getOrNull()
            val name = a?.subLocality ?: a?.locality ?: a?.featureName
            if (name != null) android.os.Handler(Looper.getMainLooper()).post { place = name; publish() }
        }.start()
    }

    private fun publish() {
        val l = location ?: return
        lastPublish = System.currentTimeMillis()
        val speed = max(if (l.hasSpeed()) l.speed.toDouble() else 0.0, 0.0) * 3.6
        onUpdate(HudSnapshot.Minimap(place.uppercase(), heading, compass(facing), "%.1f KM/H".format(Locale.US, speed), 300),
            LatLon(l.latitude, l.longitude), l)
    }

    companion object {
        fun compass(degrees: Double): String {
            val points = listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
            return points[((((degrees % 360) + 360) % 360 / 45).roundToInt()) % 8]
        }
    }
}

/**
 * The minimap's ground: CARTO's dark map tiles, stitched into one square raster around a point.
 * Dark because black is transparent on the glasses. Only the raster comes from here; the route,
 * the cone and the marks are drawn over it, so a slow or failed fetch loses none of them.
 */
object MapGround {
    private const val EQUATOR_MPP = 156_543.03392

    suspend fun raster(centre: LatLon, spanMetres: Double, sidePx: Int): Bitmap? = withContext(Dispatchers.IO) {
        val side = sidePx.coerceIn(64, 3000)
        val cosLat = cos(centre.lat * PI / 180)
        // @2x tiles: 512 pixels each over 256 of the zoom's world.
        val z = floor(log2(EQUATOR_MPP * cosLat * side / (2 * spanMetres))).toInt().coerceIn(2, 19)
        val worldMpp = EQUATOR_MPP * cosLat / (1 shl z)
        val spanWorld = spanMetres / worldMpp
        val n = 1 shl z
        val cx = (centre.lon + 180) / 360 * n * 256
        val latR = centre.lat * PI / 180
        val cy = (1 - ln(tan(latR) + 1 / cos(latR)) / PI) / 2 * n * 256
        val left = cx - spanWorld / 2
        val top = cy - spanWorld / 2
        val tx0 = floor(left / 256).toInt(); val tx1 = floor((left + spanWorld) / 256).toInt()
        val ty0 = floor(top / 256).toInt(); val ty1 = floor((top + spanWorld) / 256).toInt()
        if ((tx1 - tx0 + 1) * (ty1 - ty0 + 1) > 100) return@withContext null
        val scale = side / spanWorld
        val out = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(android.graphics.Color.BLACK)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        val tiles = coroutineScope {
            (tx0..tx1).flatMap { tx -> (ty0..ty1).map { ty -> tx to ty } }.map { (tx, ty) ->
                async {
                    if (ty < 0 || ty >= n) return@async null
                    val x = ((tx % n) + n) % n
                    val host = "abcd"[(x + ty) % 4]
                    tile("https://$host.basemaps.cartocdn.com/dark_all/$z/$x/$ty@2x.png")?.let { Triple(tx, ty, it) }
                }
            }.awaitAll()
        }
        var any = false
        for (t in tiles) {
            val (tx, ty, bmp) = t ?: continue
            any = true
            val dst = RectF(((tx * 256 - left) * scale).toFloat(), ((ty * 256 - top) * scale).toFloat(),
                (((tx + 1) * 256 - left) * scale).toFloat(), (((ty + 1) * 256 - top) * scale).toFloat())
            canvas.drawBitmap(bmp, Rect(0, 0, bmp.width, bmp.height), dst, paint)
            bmp.recycle()
        }
        if (any) out else null
    }

    private fun tile(url: String): Bitmap? = runCatching {
        val c = URL(url).openConnection() as HttpURLConnection
        c.setRequestProperty("User-Agent", "TheHud")
        c.connectTimeout = 10_000; c.readTimeout = 10_000
        if (c.responseCode != 200) null else c.inputStream.use { BitmapFactory.decodeStream(it) }
    }.getOrNull()

    /** For a test: the mercator round trip. */
    fun latitude(worldY: Double, z: Int): Double {
        val n = PI - 2 * PI * worldY / ((1 shl z) * 256)
        return 180 / PI * atan(0.5 * (exp(n) - exp(-n)))
    }
}

/** A route as the HUD needs it: the line to draw and the turns along it. */
data class RoutePlan(val destination: String, val points: List<LatLon>, val steps: List<Step>,
                     val expectedTravelTime: Double, val distance: Double) {
    data class Step(val instruction: String, val point: LatLon, val distance: Double, val maneuver: HudSnapshot.Maneuver? = null)
}

/** Search from Photon (OpenStreetMap's, by Komoot) and walking or driving routes from FOSSGIS's OSRM. */
object MapsService {
    data class Result(val point: LatLon, val place: HudSnapshot.Maps.Place)

    /** Places matching what was typed, nearest first. Only a rounded position goes, to rank them. */
    suspend fun search(query: String, near: LatLon): List<Result> = withContext(Dispatchers.IO) {
        val lang = Locale.getDefault().language.takeIf { it in setOf("en", "de", "fr", "it") }?.let { "&lang=$it" } ?: ""
        val url = "https://photon.komoot.io/api/?q=" + URLEncoder.encode(query, "UTF-8") +
            "&lat=%.2f&lon=%.2f&limit=10".format(Locale.US, near.lat, near.lon) + lang
        val body = httpGet(url) ?: throw IllegalStateException("no answer")
        val features = JSONObject(body).optJSONArray("features") ?: return@withContext emptyList()
        (0 until features.length()).mapNotNull { i ->
            val f = features.optJSONObject(i) ?: return@mapNotNull null
            val c = f.optJSONObject("geometry")?.optJSONArray("coordinates") ?: return@mapNotNull null
            val p = f.optJSONObject("properties") ?: return@mapNotNull null
            val point = LatLon(c.optDouble(1), c.optDouble(0))
            val street = listOf(p.optString("street"), p.optString("housenumber")).filter { it.isNotEmpty() }.joinToString(" ")
            val name = p.optString("name").ifEmpty { street.ifEmpty { return@mapNotNull null } }
            val detail = street.takeIf { it.isNotEmpty() && it != name } ?: p.optString("district").ifEmpty { p.optString("city") }
            point to Pair(name, detail)
        }.map { (point, nd) -> Triple(point, nd, near.metres(point)) }
            .sortedBy { it.third }.take(5)
            .map { (point, nd, m) -> Result(point, HudSnapshot.Maps.Place(nd.first, nd.second, NavigationTracker.distanceText(m))) }
    }

    /**
     * The route, from FOSSGIS's servers. The start goes to about ten metres, as a route needs; it
     * is asked for only when the wearer picks a destination.
     */
    suspend fun route(from: LatLon, to: Result, driving: Boolean): RoutePlan = withContext(Dispatchers.IO) {
        val profile = if (driving) "routed-car" else "routed-foot"
        val url = "https://routing.openstreetmap.de/$profile/route/v1/driving/" +
            "%.4f,%.4f;%.5f,%.5f".format(Locale.US, from.lon, from.lat, to.point.lon, to.point.lat) +
            "?overview=full&geometries=geojson&steps=true"
        val body = httpGet(url, timeout = 20_000) ?: throw IllegalStateException("no route")
        val route = JSONObject(body).optJSONArray("routes")?.optJSONObject(0) ?: throw IllegalStateException("no route")
        val coords = route.getJSONObject("geometry").getJSONArray("coordinates")
        val points = (0 until coords.length()).map { coords.getJSONArray(it).let { c -> LatLon(c.getDouble(1), c.getDouble(0)) } }
        val steps = mutableListOf<RoutePlan.Step>()
        val legs = route.optJSONArray("legs")
        for (l in 0 until (legs?.length() ?: 0)) {
            val s = legs!!.getJSONObject(l).optJSONArray("steps") ?: continue
            for (i in 0 until s.length()) {
                val step = s.getJSONObject(i)
                val m = step.getJSONObject("maneuver")
                val loc = m.getJSONArray("location")
                val type = m.optString("type"); val modifier = m.optString("modifier")
                steps += RoutePlan.Step(if (type == "depart") "" else instruction(type, modifier, step.optString("name")),
                    LatLon(loc.getDouble(1), loc.getDouble(0)), step.optDouble("distance"), maneuver(type, modifier))
            }
        }
        RoutePlan(to.place.name, points, steps, route.optDouble("duration"), route.optDouble("distance"))
    }

    private fun instruction(type: String, modifier: String, road: String): String {
        val onto = if (road.isNotEmpty()) " onto $road" else ""
        return when (type) {
            "arrive" -> "Arrive at the destination"
            "roundabout", "rotary", "roundabout turn" -> "At the roundabout, take the exit$onto"
            "continue", "new name" -> if (modifier.contains("left") || modifier.contains("right")) "Keep $modifier$onto" else "Continue$onto"
            else -> when (modifier) {
                "uturn" -> "Make a U-turn$onto"
                "straight" -> "Go straight$onto"
                "" -> "Continue$onto"
                else -> "Turn $modifier$onto"
            }
        }
    }

    private fun maneuver(type: String, modifier: String) = when {
        type == "arrive" -> HudSnapshot.Maneuver.arrive
        type.startsWith("roundabout") || type == "rotary" -> HudSnapshot.Maneuver.roundabout
        modifier == "uturn" -> HudSnapshot.Maneuver.uturn
        modifier == "slight left" -> HudSnapshot.Maneuver.slightLeft
        modifier == "slight right" -> HudSnapshot.Maneuver.slightRight
        modifier.contains("left") -> HudSnapshot.Maneuver.left
        modifier.contains("right") -> HudSnapshot.Maneuver.right
        else -> HudSnapshot.Maneuver.straight
    }
}

/** Follows the wearer along a route: which turn is next, how far to it, how long is left. */
class NavigationTracker(val plan: RoutePlan) {
    var stepIndex = plan.steps.indexOfFirst { it.instruction.isNotEmpty() }.takeIf { it >= 0 } ?: max(plan.steps.size - 1, 0)
        private set

    fun update(here: LatLon, now: Long = System.currentTimeMillis(), is24: Boolean = true): HudSnapshot.Maps.Navigation {
        while (stepIndex < plan.steps.size - 1 && here.metres(plan.steps[stepIndex].point) < TURN_RADIUS) stepIndex++
        val toTurn = if (plan.steps.isEmpty()) 0.0 else here.metres(plan.steps[stepIndex].point)
        val after = if (plan.steps.isEmpty()) 0.0 else plan.steps.drop(stepIndex).sumOf { it.distance }
        val remaining = toTurn + after
        val seconds = if (plan.distance > 0) plan.expectedTravelTime * min(remaining / plan.distance, 1.5) else 0.0
        val arrived = plan.points.lastOrNull()?.let { here.metres(it) < ARRIVAL_RADIUS } ?: false
        val step = plan.steps.getOrNull(stepIndex)
        val instruction = step?.instruction ?: plan.destination
        return HudSnapshot.Maps.Navigation(
            plan.destination, if (arrived) "You have arrived" else instruction,
            if (arrived) HudSnapshot.Maneuver.arrive else step?.maneuver ?: maneuver(instruction),
            distanceText(toTurn), durationText(seconds), distanceText(remaining),
            SimpleDateFormat(if (is24) "H:mm" else "h:mm", Locale.US).format(Date(now + (seconds * 1000).toLong())),
            arrived)
    }

    companion object {
        const val TURN_RADIUS = 20.0
        const val ARRIVAL_RADIUS = 25.0

        /** "40 M", "850 M", "2.4 KM". */
        fun distanceText(metres: Double): String {
            if (metres < 1000) {
                val rounded = if (metres < 100) Math.rint(metres / 5) * 5 else Math.rint(metres / 10) * 10
                return "${rounded.toInt()} M"
            }
            return (if (metres < 10_000) "%.1f KM" else "%.0f KM").format(Locale.US, metres / 1000)
        }

        /** "1 MIN", "12 MIN", "1 H 05". */
        fun durationText(seconds: Double): String {
            val minutes = max((seconds / 60).roundToInt(), 1)
            return if (minutes < 60) "$minutes MIN" else "%d H %02d".format(Locale.US, minutes / 60, minutes % 60)
        }

        /** A turn from the instruction's words, in English, Portuguese and Spanish. */
        fun maneuver(instruction: String): HudSnapshot.Maneuver {
            val text = instruction.lowercase()
            fun has(vararg words: String) = words.any { text.contains(it) }
            if (has("u-turn", "make a u", "retorno", "meia-volta", "cambio de sentido", "media vuelta")) return HudSnapshot.Maneuver.uturn
            if (has("roundabout", "rotunda", "rotatória", "rotatoria", "glorieta")) return HudSnapshot.Maneuver.roundabout
            if (has("destination", "arrive", "destino", "chegada", "llegada")) return HudSnapshot.Maneuver.arrive
            val slight = has("slight", "bear", "ligeiramente", "levemente", "ligeramente", "mantenha", "keep")
            if (has("left", "esquerda", "izquierda")) return if (slight) HudSnapshot.Maneuver.slightLeft else HudSnapshot.Maneuver.left
            if (has("right", "direita", "derecha")) return if (slight) HudSnapshot.Maneuver.slightRight else HudSnapshot.Maneuver.right
            return HudSnapshot.Maneuver.straight
        }
    }
}
