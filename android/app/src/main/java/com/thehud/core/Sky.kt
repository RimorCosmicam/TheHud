package com.thehud.core

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import io.github.cosinekitty.astronomy.Aberration
import io.github.cosinekitty.astronomy.Body
import io.github.cosinekitty.astronomy.Direction
import io.github.cosinekitty.astronomy.EquatorEpoch
import io.github.cosinekitty.astronomy.Observer
import io.github.cosinekitty.astronomy.Refraction
import io.github.cosinekitty.astronomy.Time
import io.github.cosinekitty.astronomy.eclipticGeoMoon
import io.github.cosinekitty.astronomy.equator
import io.github.cosinekitty.astronomy.horizon
import io.github.cosinekitty.astronomy.illumination
import io.github.cosinekitty.astronomy.moonPhase
import io.github.cosinekitty.astronomy.searchAltitude
import io.github.cosinekitty.astronomy.searchRiseSet
import io.github.cosinekitty.astronomy.sunPosition
import kotlinx.serialization.Serializable
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.tan

// The sky, as the iPhone app works it out: Astronomy Engine for the sun, the moon, the planets and
// the turning of the catalogue's fixed stars into the local sky; d3-celestial's catalogue (the
// same sky.json, shared from the iPhone sources) for the stars and figures.

/** The twelve signs of the tropical zodiac, thirty degrees of ecliptic longitude each. */
enum class Zodiac(val title: String, val dates: String) {
    aries("ARIES", "MAR 21 – APR 19"), taurus("TAURUS", "APR 20 – MAY 20"), gemini("GEMINI", "MAY 21 – JUN 20"),
    cancer("CANCER", "JUN 21 – JUL 22"), leo("LEO", "JUL 23 – AUG 22"), virgo("VIRGO", "AUG 23 – SEP 22"),
    libra("LIBRA", "SEP 23 – OCT 22"), scorpio("SCORPIO", "OCT 23 – NOV 21"), sagittarius("SAGITTARIUS", "NOV 22 – DEC 21"),
    capricorn("CAPRICORN", "DEC 22 – JAN 19"), aquarius("AQUARIUS", "JAN 20 – FEB 18"), pisces("PISCES", "FEB 19 – MAR 20");

    /** The sign's glyph, asked for as text rather than emoji. */
    val glyph: String get() = String(Character.toChars(0x2648 + ordinal)) + "︎"

    companion object {
        fun of(longitude: Double): Zodiac {
            val d = ((longitude % 360) + 360) % 360
            return entries[(d / 30).toInt().coerceIn(0, 11)]
        }
        /** d3-celestial's ids for the constellations the signs are named after. */
        val constellations = setOf("Ari", "Tau", "Gem", "Cnc", "Leo", "Vir", "Lib", "Sco", "Sgr", "Cap", "Aqr", "Psc")
    }
}

/** What the sky app draws over the stars. */
@Serializable
enum class SkyLayer(val title: String) {
    figures("FIGURES"), names("NAMES"), zodiac("ZODIAC"), milkyWay("MILKY WAY"), planes("PLANES"), iss("ISS"), grid("GRID");

    companion object {
        val standard = setOf(figures, names, zodiac, milkyWay, planes, iss)
    }
}

/** The sky app's settings: what it shows, and how wide a piece of sky fills the glasses. */
data class SkyView(
    val layers: Set<SkyLayer> = SkyLayer.standard,
    /** Degrees of sky across the glasses. */
    val fov: Double = STANDARD_FOV,
    /** Degrees turned from where the phone faces. */
    val pan: Double = 0.0,
    /** Degrees looked up from the usual view. */
    val tilt: Double = 0.0,
    /** The thing picked on the phone to be pointed out. */
    val selected: String? = null,
) {
    val isAdjusted get() = pan != 0.0 || tilt != 0.0 || fov != STANDARD_FOV

    fun recentred() = copy(pan = 0.0, tilt = 0.0, fov = STANDARD_FOV)
    fun zoomed(notches: Int) = zoomed(1.08.pow(notches))
    fun zoomed(factor: Double): SkyView {
        if (!factor.isFinite() || factor <= 0) return this
        return copy(fov = (fov * factor).coerceIn(40.0, 170.0))
    }
    fun looked(dPan: Double, dTilt: Double) = copy(
        pan = ((pan + dPan + 180) % 360 + 360) % 360 - 180,
        tilt = (tilt + dTilt).coerceIn(0.0, 70.0))
    fun toggled(layer: SkyLayer) = copy(layers = if (layer in layers) layers - layer else layers + layer)

    companion object { const val STANDARD_FOV = 110.0 }
}

object SkyModel {
    /** Compass point for an azimuth: "N", "NE", ... */
    fun compass(azimuth: Double): String {
        val points = listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
        return points[(((azimuth % 360) + 360 + 22.5) / 45).toInt() % 8]
    }

    val phaseNames = listOf("NEW MOON", "WAXING CRESCENT", "FIRST QUARTER", "WAXING GIBBOUS",
        "FULL MOON", "WANING GIBBOUS", "LAST QUARTER", "WANING CRESCENT")

    fun phaseIndex(angle: Double) = (((angle % 360) + 360 + 22.5) / 45).toInt() % 8

    fun compute(at: Date, latitude: Double, longitude: Double, catalogue: SkyCatalogue?,
                zone: TimeZone = TimeZone.getDefault(), is24: Boolean = true): HudSnapshot.Sky {
        val observer = Observer(latitude, longitude, 0.0)
        val time = Time.fromMillisecondsSince1970(at.time)
        val clock = SimpleDateFormat(if (is24) "H:mm" else "h:mm", Locale.US).apply { timeZone = zone }
        fun text(t: Time?) = t?.let { clock.format(Date(it.toMillisecondsSince1970())) }

        // The day, searched from local midnight, so it is today's sunrise even after it.
        val midnight = Calendar.getInstance(zone).also { it.time = at }.apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis.let { Time.fromMillisecondsSince1970(it) }
        val rise = runCatching { searchRiseSet(Body.Sun, observer, Direction.Rise, midnight, 1.0, 0.0) }.getOrNull()
        val set = runCatching { searchRiseSet(Body.Sun, observer, Direction.Set, midnight, 1.0, 0.0) }.getOrNull()
        val golden = runCatching { searchAltitude(Body.Sun, observer, Direction.Set, midnight, 1.0, 6.0) }.getOrNull()
        val progress = if (rise != null && set != null) ((time.ut - rise.ut) / (set.ut - rise.ut)).takeIf { it in 0.0..1.0 } else null

        val angle = runCatching { moonPhase(time) }.getOrDefault(0.0)
        val phase = phaseIndex(angle)
        val lit = runCatching { (illumination(Body.Moon, time).phaseFraction * 100).roundToInt() }.getOrDefault(0)

        var sunAltitude = 0.0
        val bodies = listOf(Body.Sun to HudSnapshot.Sky.Body.Kind.sun, Body.Moon to HudSnapshot.Sky.Body.Kind.moon,
            Body.Mercury to HudSnapshot.Sky.Body.Kind.planet, Body.Venus to HudSnapshot.Sky.Body.Kind.planet,
            Body.Mars to HudSnapshot.Sky.Body.Kind.planet, Body.Jupiter to HudSnapshot.Sky.Body.Kind.planet,
            Body.Saturn to HudSnapshot.Sky.Body.Kind.planet).mapNotNull { (body, kind) ->
            runCatching {
                val eq = equator(body, time, observer, EquatorEpoch.OfDate, Aberration.Corrected)
                val h = horizon(time, observer, eq.ra, eq.dec, Refraction.Normal)
                if (kind == HudSnapshot.Sky.Body.Kind.sun) sunAltitude = h.altitude
                val mag = runCatching { illumination(body, time).mag }.getOrDefault(0.0)
                HudSnapshot.Sky.Body(kind, body.name.uppercase(), h.azimuth, h.altitude, mag)
            }.getOrNull()
        }

        var sky = HudSnapshot.Sky(
            hasLocation = true, sunrise = text(rise), sunset = text(set), goldenHour = text(golden),
            dayProgress = progress, sunAltitude = sunAltitude, moonPhase = phaseNames[phase], moonPhaseIndex = phase,
            moonIllumination = lit,
            moonrise = text(runCatching { searchRiseSet(Body.Moon, observer, Direction.Rise, time, 1.0, 0.0) }.getOrNull()),
            moonset = text(runCatching { searchRiseSet(Body.Moon, observer, Direction.Set, time, 1.0, 0.0) }.getOrNull()),
            bodies = bodies,
            sunSign = runCatching { Zodiac.of(sunPosition(time).elon) }.getOrNull(),
            moonSign = runCatching { Zodiac.of(eclipticGeoMoon(time).lon) }.getOrNull(),
        )
        val cat = catalogue ?: return sky

        // The catalogue's positions are for the year 2000; the drift since is far below what a
        // chart this size shows.
        fun local(ra: Float, dec: Float): HudSnapshot.Sky.Point {
            val h = horizon(time, observer, ra / 15.0, dec.toDouble(), Refraction.Normal)
            return HudSnapshot.Sky.Point(h.azimuth.toFloat(), h.altitude.toFloat())
        }
        val stars = ArrayList<HudSnapshot.Sky.Star>(cat.stars.size / 2)
        for (s in cat.stars) {
            val p = local(s.ra, s.dec)
            if (p.alt > -1) stars.add(HudSnapshot.Sky.Star(p.az, p.alt, s.mag, s.bv))
        }
        val lines = cat.lines.mapNotNull { line ->
            val points = line.points.map { local(it.ra, it.dec) }
            if (points.none { it.alt > 0 }) null else HudSnapshot.Sky.Figure(points, line.id in Zodiac.constellations)
        }
        val labels = cat.constellations.mapNotNull { l ->
            val p = local(l.ra, l.dec)
            if (p.alt > 2) HudSnapshot.Sky.Label(p.az, p.alt, l.name, l.id in Zodiac.constellations) else null
        }
        val milky = cat.milkyWay.mapNotNull { band ->
            val points = band.points.map { local(it.ra, it.dec) }.filter { it.alt > -3 }
            if (points.isEmpty()) null else HudSnapshot.Sky.Band(band.level, points)
        }
        // The ecliptic, from ecliptic longitude straight to the sky: on it the latitude is nought.
        val tiltR = 23.4393 * PI / 180
        fun onEcliptic(lon: Double): HudSnapshot.Sky.Point {
            val l = lon * PI / 180
            val ra = atan2(sin(l) * cos(tiltR), cos(l)) * 180 / PI
            val dec = asin(sin(tiltR) * sin(l)) * 180 / PI
            return local((((ra + 360) % 360)).toFloat(), dec.toFloat())
        }
        val ecliptic = (0..180).map { onEcliptic(it * 2.0) }
        val signs = Zodiac.entries.map { z -> onEcliptic(z.ordinal * 30.0 + 15).let { HudSnapshot.Sky.Sign(z, it.az, it.alt) } }
        val names = cat.names.mapNotNull { l ->
            val p = local(l.ra, l.dec)
            if (p.alt > 2) HudSnapshot.Sky.Label(p.az, p.alt, l.name) else null
        }
        sky = sky.copy(stars = stars, lines = lines, constellations = labels, milkyWay = milky, ecliptic = ecliptic,
            signs = signs, starNames = names)
        return sky
    }
}

/** The star catalogue, read once: stars to magnitude 5.5, the figures, names, and the Milky Way. */
class SkyCatalogue(json: String) {
    class Star(val ra: Float, val dec: Float, val mag: Float, val bv: Float)
    class Point(val ra: Float, val dec: Float)
    class Label(val ra: Float, val dec: Float, val name: String, val id: String = "")
    class Line(val id: String, val points: List<Point>)
    class Band(val level: Int, val points: List<Point>)

    val stars: List<Star>
    val lines: List<Line>
    val constellations: List<Label>
    val names: List<Label>
    val milkyWay: List<Band>

    init {
        val root = JSONObject(json)
        fun f(a: JSONArray, i: Int) = a.optDouble(i, 0.0).toFloat()
        fun points(a: JSONArray) = (0 until a.length()).mapNotNull { i ->
            a.optJSONArray(i)?.takeIf { it.length() >= 2 }?.let { Point(f(it, 0), f(it, 1)) }
        }
        fun labels(a: JSONArray) = (0 until a.length()).mapNotNull { i ->
            a.optJSONArray(i)?.takeIf { it.length() >= 3 }?.let {
                Label(f(it, 0), f(it, 1), it.optString(2), if (it.length() > 3) it.optString(3) else "")
            }
        }
        val s = root.getJSONArray("stars")
        stars = (0 until s.length()).mapNotNull { i ->
            s.optJSONArray(i)?.takeIf { it.length() >= 4 }?.let { Star(f(it, 0), f(it, 1), f(it, 2), f(it, 3)) }
        }
        val l = root.getJSONArray("lines")
        lines = (0 until l.length()).map { i -> l.getJSONObject(i).let { Line(it.optString("c"), points(it.getJSONArray("p"))) } }
        constellations = labels(root.getJSONArray("labels"))
        names = labels(root.getJSONArray("names"))
        val m = root.getJSONArray("milkyWay")
        milkyWay = (0 until m.length()).mapNotNull { i ->
            val row = m.optJSONArray(i) ?: return@mapNotNull null
            if (row.length() != 2) null else Band(row.optInt(0), points(row.getJSONArray(1)))
        }
    }
}

/**
 * The sky as it is seen: the horizon low across the glasses in the direction the phone faces, in
 * a stereographic projection (it keeps shapes, so the constellations look like themselves).
 */
class SkyProjection(val facing: Double, fov: Double, tilt: Double = 0.0,
                    val size: Size = Size(HudTheme.CANVAS_WIDTH, HudTheme.CANVAS_HEIGHT)) {
    val scale: Double = size.width / 2 / (2 * tan(fov * PI / 720))
    val centreAlt: Double = min(2 * atan(size.height * 0.34 / (2 * scale)) * 180 / PI + tilt, 89.0)

    fun project(az: Double, alt: Double): Offset? {
        val d = (az - facing) * PI / 180
        val p = alt * PI / 180
        val p0 = centreAlt * PI / 180
        val cosc = sin(p0) * sin(p) + cos(p0) * cos(p) * cos(d)
        if (cosc <= -0.6) return null
        val k = 2 / (1 + cosc)
        val x = k * cos(p) * sin(d)
        val y = k * (cos(p0) * sin(p) - sin(p0) * cos(p) * cos(d))
        return Offset((size.width / 2 + scale * x).toFloat(), (size.height / 2 - scale * y).toFloat())
    }

    fun project(p: HudSnapshot.Sky.Point) = project(p.az.toDouble(), p.alt.toDouble())
    fun project(p: HudSnapshot.Overhead.Point) = project(p.az, p.alt)

    class Horizon(val centre: Offset, val radius: Float, val groundInside: Boolean)

    /** The horizon, which this projection always draws as a circle, and whether the ground is inside it. */
    fun horizon(): Horizon? {
        val a = project(facing - 90, 0.0) ?: return null
        val b = project(facing, 0.0) ?: return null
        val c = project(facing + 90, 0.0) ?: return null
        val d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        if (abs(d) < 1e-6) return null
        val a2 = a.x * a.x + a.y * a.y
        val b2 = b.x * b.x + b.y * b.y
        val c2 = c.x * c.x + c.y * c.y
        val centre = Offset((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
            (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
        val radius = hypot(a.x - centre.x, a.y - centre.y)
        val below = project(facing, -20.0) ?: return null
        return Horizon(centre, radius, hypot(below.x - centre.x, below.y - centre.y) < radius)
    }

    fun visible(p: Offset, margin: Float = 40f) =
        p.x > -margin && p.x < size.width + margin && p.y > -margin && p.y < size.height + margin
}

/** Something in the sky the phone can point out. */
data class SkyTarget(
    val id: String, val kind: Kind, val name: String, val detail: String, val facts: List<Fact>,
    val az: Double, val alt: Double,
) {
    enum class Kind(val title: String) {
        plane("AIRCRAFT"), station("SPACE STATION"), sun("STAR"), moon("MOON"), planet("PLANET"),
        star("BRIGHT STAR"), sign("ZODIAC")
    }
    data class Fact(val label: String, val value: String)

    val isUp get() = alt > 0

    companion object {
        private fun place(az: Double, alt: Double) = Fact("UP", "${alt.roundToInt()}° · ${SkyModel.compass(az)}")
        private fun n(v: Double) = "%,d".format(Locale.US, v.roundToInt())

        fun all(sky: HudSnapshot.Sky, overhead: HudSnapshot.Overhead, layers: Set<SkyLayer>): List<SkyTarget> {
            val targets = mutableListOf<SkyTarget>()
            if (SkyLayer.iss in layers) overhead.station?.let { s ->
                targets += SkyTarget("iss", Kind.station, "ISS", "International Space Station",
                    listOf(place(s.position.az, s.position.alt), Fact("HEIGHT", "${s.altitude.roundToInt()} KM"),
                        Fact("SPEED", "${n(s.speed)} KM/H"), Fact("AWAY", "${n(s.distance)} KM"),
                        Fact("LIGHT", if (s.sunlit) "SUNLIT" else "IN SHADOW")),
                    s.position.az, s.position.alt)
            }
            if (SkyLayer.planes in layers) for (p in overhead.planes) {
                targets += SkyTarget("plane:" + p.id, Kind.plane, p.callsign, listOfNotNull(p.airline, p.model).joinToString(" · "),
                    listOf(place(p.position.az, p.position.alt), Fact("HEIGHT", "${n(p.altitude)} M"),
                        Fact("SPEED", "${p.speed.roundToInt()} KM/H"), Fact("AWAY", "${p.distance.roundToInt()} KM"),
                        Fact("FLYING", SkyModel.compass(p.track))),
                    p.position.az, p.position.alt)
            }
            for (b in sky.bodies.sortedBy { it.mag }) {
                val facts = mutableListOf(place(b.az, b.alt))
                val kind: Kind
                val detail: String
                when (b.kind) {
                    HudSnapshot.Sky.Body.Kind.sun -> {
                        kind = Kind.sun; detail = "Our star"
                        sky.sunSign?.let { facts += Fact("IN", it.title) }
                        sky.sunset?.let { facts += Fact("SETS", it) }
                    }
                    HudSnapshot.Sky.Body.Kind.moon -> {
                        kind = Kind.moon; detail = sky.moonPhase.lowercase().split(" ").joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
                        facts += Fact("LIT", "${sky.moonIllumination}%")
                        sky.moonSign?.let { facts += Fact("IN", it.title) }
                    }
                    HudSnapshot.Sky.Body.Kind.planet -> {
                        kind = Kind.planet; detail = "Planet"
                        facts += Fact("BRIGHTNESS", "%.1f".format(Locale.US, b.mag))
                    }
                }
                targets += SkyTarget("body:" + b.name, kind, b.name, detail, facts, b.az, b.alt)
            }
            for (s in sky.starNames) if (s.alt > 8) {
                targets += SkyTarget("star:" + s.name, Kind.star, s.name.uppercase(), "Star",
                    listOf(place(s.az.toDouble(), s.alt.toDouble())), s.az.toDouble(), s.alt.toDouble())
            }
            if (SkyLayer.zodiac in layers) for (sign in sky.signs) if (sign.alt > 0) {
                val facts = mutableListOf(Fact("SUN IN IT", sign.sign.dates), place(sign.az.toDouble(), sign.alt.toDouble()))
                if (sky.sunSign == sign.sign) facts += Fact("NOW", "THE SUN IS HERE")
                if (sky.moonSign == sign.sign) facts += Fact("NOW", "THE MOON IS HERE")
                targets += SkyTarget("sign:${sign.sign.ordinal}", Kind.sign, sign.sign.glyph + " " + sign.sign.title,
                    "Sign of the zodiac", facts, sign.az.toDouble(), sign.alt.toDouble())
            }
            return targets
        }
    }
}
