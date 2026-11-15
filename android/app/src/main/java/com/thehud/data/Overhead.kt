package com.thehud.data

import com.thehud.core.HudSnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** Where something in the air is, seen from the ground. The earth as a sphere, plenty for the glasses. */
object SkyGeometry {
    private const val EARTH_RADIUS = 6_371_000.0

    data class Look(val az: Double, val alt: Double, val distance: Double)

    fun look(lat0: Double, lon0: Double, lat: Double, lon: Double, height: Double): Look {
        fun ecef(la: Double, lo: Double, h: Double): Triple<Double, Double, Double> {
            val r = EARTH_RADIUS + h; val p = Math.toRadians(la); val l = Math.toRadians(lo)
            return Triple(r * cos(p) * cos(l), r * cos(p) * sin(l), r * sin(p))
        }
        val o = ecef(lat0, lon0, 0.0); val t = ecef(lat, lon, height)
        val dx = t.first - o.first; val dy = t.second - o.second; val dz = t.third - o.third
        val p = Math.toRadians(lat0); val l = Math.toRadians(lon0)
        val east = -sin(l) * dx + cos(l) * dy
        val north = -sin(p) * cos(l) * dx - sin(p) * sin(l) * dy + cos(p) * dz
        val up = cos(p) * cos(l) * dx + cos(p) * sin(l) * dy + sin(p) * dz
        var az = Math.toDegrees(atan2(east, north))
        if (az < 0) az += 360
        return Look(az, Math.toDegrees(atan2(up, hypot(east, north))), sqrt(dx * dx + dy * dy + dz * dz))
    }

    fun move(lat: Double, lon: Double, track: Double, metres: Double): Pair<Double, Double> {
        val t = Math.toRadians(track)
        return (lat + metres * cos(t) / 111_320) to
            (lon + metres * sin(t) / (111_320 * max(cos(Math.toRadians(lat)), 0.01)))
    }
}

/**
 * Aircraft from adsb.lol's open feed and the space station from wheretheiss.at, kept between
 * fetches and flown on along their tracks, as on the iPhone.
 */
class OverheadProvider(private val scope: CoroutineScope) {
    private class Fix(val lat: Double, val lon: Double, val alt: Double)
    private class Track(val callsign: String, val model: String?, val fix: Fix, val speed: Double, val track: Double,
                        val climb: Double, val at: Long, val history: List<Fix>)
    private class StationFix(val at: Long, val lat: Double, val lon: Double, val alt: Double, val speed: Double, val sunlit: Boolean)

    private var tracks = mapOf<String, Track>()
    private var station = listOf<StationFix>()
    private var status = ""
    private var lastPlanes = 0L
    private var lastStation = 0L
    private var fetchingPlanes = false
    private var fetchingStation = false

    fun refresh(lat: Double, lon: Double, planes: Boolean, wantsStation: Boolean, now: Long = System.currentTimeMillis()) {
        if (planes && !fetchingPlanes && now - lastPlanes > 15_000) {
            fetchingPlanes = true; lastPlanes = now
            scope.launch { fetchPlanes(lat, lon); fetchingPlanes = false }
        }
        if (wantsStation && !fetchingStation && now - lastStation > 60_000) {
            fetchingStation = true; lastStation = now
            scope.launch { fetchStation(now); fetchingStation = false }
        }
    }

    private suspend fun fetchPlanes(lat: Double, lon: Double) {
        // Rounded to a kilometre or so: the feed needs where to look, not where you stand.
        val body = withContext(Dispatchers.IO) {
            httpGet("https://api.adsb.lol/v2/point/%.2f/%.2f/80".format(Locale.US, lat, lon))
        }
        val reported = body?.let { runCatching { decodePlanes(it) }.getOrNull() }
        if (reported == null) { if (tracks.isEmpty()) status = "NO FLIGHT DATA"; return }
        val now = System.currentTimeMillis()
        tracks = reported.associate { r ->
            val history = (tracks[r.id]?.let { it.history + it.fix } ?: emptyList()).takeLast(5)
            r.id to Track(r.callsign, r.model, r.fix, r.speed, r.track, r.climb, now - (r.age * 1000).toLong(), history)
        }
        status = ""
    }

    private class Reported(val id: String, val callsign: String, val model: String?, val fix: Fix,
                           val speed: Double, val track: Double, val climb: Double, val age: Double)

    private fun decodePlanes(body: String): List<Reported> {
        val list = JSONObject(body).optJSONArray("ac") ?: return emptyList()
        return (0 until list.length()).mapNotNull { i ->
            val ac = list.optJSONObject(i) ?: return@mapNotNull null
            fun d(k: String) = if (ac.has(k) && !ac.isNull(k)) ac.opt(k).let { (it as? Number)?.toDouble() } else null
            val id = ac.optString("hex").ifEmpty { return@mapNotNull null }
            val lat = d("lat") ?: return@mapNotNull null
            val lon = d("lon") ?: return@mapNotNull null
            // alt_baro is "ground" for aircraft on the ground, which is not a number and is left out.
            val feet = d("alt_geom") ?: d("alt_baro") ?: return@mapNotNull null
            if (feet <= 50) return@mapNotNull null
            val flight = ac.optString("flight").trim()
            Reported(id, flight.ifEmpty { ac.optString("r").ifEmpty { id.uppercase() } },
                ac.optString("t").ifEmpty { null }, Fix(lat, lon, feet * 0.3048),
                (d("gs") ?: 0.0) * 0.514444, d("track") ?: 0.0,
                (d("geom_rate") ?: d("baro_rate") ?: 0.0) * 0.3048 / 60, d("seen_pos") ?: 0.0)
        }
    }

    private suspend fun fetchStation(now: Long) {
        // Its next minutes, 45 seconds apart, to fly it between fetches and draw its way.
        val start = now / 1000 - 15
        val stamps = (0 until 10).joinToString(",") { (start + it * 45).toString() }
        val body = withContext(Dispatchers.IO) {
            httpGet("https://api.wheretheiss.at/v1/satellites/25544/positions?timestamps=$stamps&units=kilometers")
        } ?: return
        val fixes = runCatching {
            val a = JSONArray(body)
            (0 until a.length()).mapNotNull { i ->
                val r = a.optJSONObject(i) ?: return@mapNotNull null
                StationFix((r.optDouble("timestamp") * 1000).toLong(), r.optDouble("latitude"), r.optDouble("longitude"),
                    r.optDouble("altitude"), r.optDouble("velocity", 27_600.0), r.optString("visibility") != "eclipsed")
            }.sortedBy { it.at }
        }.getOrNull()
        if (!fixes.isNullOrEmpty()) station = fixes
    }

    fun overhead(lat: Double, lon: Double, now: Long = System.currentTimeMillis()): HudSnapshot.Overhead {
        fun look(f: Fix) = SkyGeometry.look(lat, lon, f.lat, f.lon, f.alt).let { HudSnapshot.Overhead.Point(it.az, it.alt) to it.distance }
        fun flown(t: Track, seconds: Double): Fix {
            val (la, lo) = SkyGeometry.move(t.fix.lat, t.fix.lon, t.track, t.speed * seconds)
            return Fix(la, lo, max(t.fix.alt + t.climb * seconds, 0.0))
        }
        val planes = tracks.mapNotNull { (id, t) ->
            // Not flown on for ever: a plane the feed has lost stops where it was last seen.
            val age = min(max((now - t.at) / 1000.0, 0.0), 60.0)
            val fix = flown(t, age)
            val (here, distance) = look(fix)
            if (here.alt <= -1) return@mapNotNull null
            HudSnapshot.Overhead.Plane(id, t.callsign, Aviation.airline(t.callsign), t.model?.let(Aviation::model),
                fix.alt, t.speed * 3.6, distance / 1000, t.track, here, look(flown(t, age + 30)).first,
                (t.history + fix).map { look(it).first })
        }.sortedBy { it.distance }

        val s = stationFix(now)?.let { f ->
            val (here, distance) = look(Fix(f.lat, f.lon, f.alt * 1000))
            HudSnapshot.Overhead.Station(here, f.alt, f.speed, distance / 1000, f.sunlit,
                station.map { look(Fix(it.lat, it.lon, it.alt * 1000)).first })
        }
        return HudSnapshot.Overhead(planes, s, status)
    }

    private fun stationFix(at: Long): StationFix? {
        val after = station.indexOfFirst { it.at > at }
        if (after <= 0) return null
        val a = station[after - 1]; val b = station[after]
        val t = (at - a.at).toDouble() / (b.at - a.at)
        var dLon = b.lon - a.lon
        if (dLon > 180) dLon -= 360 else if (dLon < -180) dLon += 360
        var lon = a.lon + dLon * t
        if (lon > 180) lon -= 360 else if (lon < -180) lon += 360
        return StationFix(at, a.lat + (b.lat - a.lat) * t, lon, a.alt + (b.alt - a.alt) * t, a.speed, a.sunlit)
    }
}

/** Names for the feed's codes: airlines by a callsign's three letters, aircraft by ICAO type. */
object Aviation {
    fun airline(callsign: String): String? {
        val prefix = callsign.take(3).uppercase()
        if (prefix.length != 3 || !prefix.all { it.isLetter() } || callsign.getOrNull(3)?.isDigit() != true) return null
        return airlines[prefix]
    }

    fun model(code: String) = models[code.uppercase()] ?: code

    private val airlines = mapOf(
        "TAP" to "TAP Air Portugal", "RYR" to "Ryanair", "EZY" to "easyJet", "EJU" to "easyJet Europe",
        "EZS" to "easyJet Switzerland", "VLG" to "Vueling", "IBE" to "Iberia", "IBS" to "Iberia Express",
        "ANE" to "Air Nostrum", "AEA" to "Air Europa", "BAW" to "British Airways", "VIR" to "Virgin Atlantic",
        "EIN" to "Aer Lingus", "AFR" to "Air France", "KLM" to "KLM", "TRA" to "Transavia",
        "TVF" to "Transavia France", "DLH" to "Lufthansa", "EWG" to "Eurowings", "SWR" to "Swiss",
        "AUA" to "Austrian", "BEL" to "Brussels Airlines", "ITY" to "ITA Airways", "SAS" to "SAS",
        "FIN" to "Finnair", "ICE" to "Icelandair", "NAX" to "Norwegian", "NSZ" to "Norwegian",
        "WZZ" to "Wizz Air", "LOT" to "LOT", "AEE" to "Aegean", "BTI" to "airBaltic", "LGL" to "Luxair",
        "THY" to "Turkish Airlines", "PGT" to "Pegasus", "UAE" to "Emirates", "QTR" to "Qatar Airways",
        "ETD" to "Etihad", "SVA" to "Saudia", "MSR" to "EgyptAir", "RAM" to "Royal Air Maroc",
        "ETH" to "Ethiopian", "SAA" to "South African", "UAL" to "United", "AAL" to "American",
        "DAL" to "Delta", "SWA" to "Southwest", "JBU" to "JetBlue", "ACA" to "Air Canada",
        "WJA" to "WestJet", "AMX" to "Aeroméxico", "AVA" to "Avianca", "LAN" to "LATAM",
        "TAM" to "LATAM Brasil", "LPE" to "LATAM Peru", "GLO" to "Gol", "AZU" to "Azul",
        "PTB" to "Voepass", "ARG" to "Aerolíneas Argentinas", "CMP" to "Copa", "SKU" to "Sky Airline",
        "ANA" to "All Nippon", "JAL" to "Japan Airlines", "CPA" to "Cathay Pacific",
        "SIA" to "Singapore Airlines", "QFA" to "Qantas", "KAL" to "Korean Air",
        "CES" to "China Eastern", "CSN" to "China Southern", "CCA" to "Air China",
        "FDX" to "FedEx", "UPS" to "UPS", "DHK" to "DHL", "BCS" to "DHL", "GEC" to "Lufthansa Cargo",
        "CLX" to "Cargolux", "NJE" to "NetJets", "EJA" to "NetJets", "SAT" to "Azores Airlines",
        "RZO" to "Azores Airlines", "BCY" to "CityJet", "VOE" to "Volotea", "CFG" to "Condor",
    )

    private val models = mapOf(
        "A319" to "A319", "A320" to "A320", "A321" to "A321", "A20N" to "A320neo", "A21N" to "A321neo",
        "A19N" to "A319neo", "BCS1" to "A220-100", "BCS3" to "A220-300", "A332" to "A330-200",
        "A333" to "A330-300", "A338" to "A330-800neo", "A339" to "A330-900neo", "A359" to "A350-900",
        "A35K" to "A350-1000", "A388" to "A380", "B737" to "737-700", "B738" to "737-800",
        "B739" to "737-900", "B37M" to "737 MAX 7", "B38M" to "737 MAX 8", "B39M" to "737 MAX 9",
        "B3XM" to "737 MAX 10", "B752" to "757-200", "B763" to "767-300", "B772" to "777-200",
        "B77W" to "777-300ER", "B77L" to "777-200LR", "B788" to "787-8", "B789" to "787-9",
        "B78X" to "787-10", "B744" to "747-400", "B748" to "747-8", "E170" to "E170", "E75L" to "E175",
        "E190" to "E190", "E195" to "E195", "E290" to "E190-E2", "E295" to "E195-E2", "AT72" to "ATR 72",
        "AT75" to "ATR 72-500", "AT76" to "ATR 72-600", "DH8D" to "Dash 8-400", "CRJ9" to "CRJ900",
        "C172" to "Cessna 172", "C152" to "Cessna 152", "P28A" to "Piper Cherokee", "PC12" to "Pilatus PC-12",
        "GLF6" to "Gulfstream G650", "GLEX" to "Global Express", "C68A" to "Citation Latitude",
        "EC35" to "H135 helicopter", "EC45" to "H145 helicopter", "A139" to "AW139 helicopter",
    )
}
