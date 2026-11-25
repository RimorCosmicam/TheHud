package com.thehud.data

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import com.thehud.core.HudSnapshot
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Steps today, from the phone's step counter. The counter runs from the last boot, so the count at
 * the first reading of the day is kept, and each hour's steps are kept beside it for the bars.
 */
class ActivityProvider(private val context: Context, private val prefs: SharedPreferences,
                       private val onChange: (HudSnapshot.Activity?) -> Unit) : SensorEventListener {
    var goal = 8000
        set(value) { field = value; publish() }
    private var started = false
    private var steps = 0

    val allowed get() = context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED

    fun start() {
        if (started) return
        val manager = context.getSystemService(SensorManager::class.java)
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sensor == null || !allowed) { onChange(null); return }
        started = true
        manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
        restore()
        publish()
    }

    /** Off: the step counter let go. */
    fun stop() {
        if (!started) return
        started = false
        context.getSystemService(SensorManager::class.java)?.unregisterListener(this)
    }

    private fun today() = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    private fun hourNow() = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)

    private fun hourly(): MutableList<Int> {
        val saved = if (prefs.getString("stepsDay", null) == today()) prefs.getString("stepsHourly", "") ?: "" else ""
        val list = saved.split(",").mapNotNull { it.toIntOrNull() }.toMutableList()
        while (list.size < hourNow() + 1) list.add(0)
        return list
    }

    private fun restore() {
        steps = if (prefs.getString("stepsDay", null) == today()) prefs.getInt("stepsToday", 0) else 0
    }

    override fun onSensorChanged(event: SensorEvent) {
        val counter = event.values.firstOrNull()?.toInt() ?: return
        val day = today()
        val edit = prefs.edit()
        var base = prefs.getInt("stepsBase", -1)
        var last = prefs.getInt("stepsCounter", -1)
        var hours = hourly()
        if (prefs.getString("stepsDay", null) != day) {
            // A new day starts from what the counter says now.
            base = counter; last = counter; steps = 0; hours = MutableList(hourNow() + 1) { 0 }
            edit.putString("stepsDay", day)
        }
        // After a restart the counter is back near nought: carry on from today's count.
        if (counter < last || base < 0) { base = counter - steps; last = counter }
        val added = counter - last
        steps = counter - base
        if (added > 0) hours[hourNow()] = hours[hourNow()] + added
        edit.putInt("stepsBase", base).putInt("stepsCounter", counter).putInt("stepsToday", steps)
            .putString("stepsHourly", hours.joinToString(",")).apply()
        publish(hours)
    }

    private fun publish(hours: List<Int> = hourly()) {
        if (!started) return
        // A stride of about three quarters of a metre: the phone has no better idea.
        onChange(HudSnapshot.Activity(steps, goal, steps * 0.00075, null, hours))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
