package com.thehud.remote

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import kotlin.math.sqrt

/**
 * The phone as an air mouse, as on the iPhone: turning it moves the cursor, read from the gyro
 * and laid level with gravity, so it works however the phone is held.
 */
class AirPointer {
    var gain = 2200.0
    var speed = 1.0
    var deadZone = 0.02
    private var rx = 0.0
    private var ry = 0.0
    private var heldUntil = 0L

    fun hold(untilMs: Long) { heldUntil = maxOf(heldUntil, untilMs); rx = 0.0; ry = 0.0 }
    fun release() { heldUntil = 0; rx = 0.0; ry = 0.0 }

    /**
     * Android's gravity points away from the ground (flat on a table it is +z), the iPhone's
     * toward it: so here it is "up" as it comes.
     */
    fun step(rotation: FloatArray, gravity: FloatArray, dt: Double, nowMs: Long): Pair<Int, Int> {
        if (dt <= 0 || dt >= 0.2 || nowMs < heldUntil) return 0 to 0
        val g = sqrt(gravity.sumOf { (it * it).toDouble() })
        if (g < 0.1) return 0 to 0
        val up = DoubleArray(3) { gravity[it] / g }
        // The phone's left-right edge, laid level.
        val right = doubleArrayOf(1 - up[0] * up[0], -up[1] * up[0], -up[2] * up[0])
        val length = sqrt(right.sumOf { it * it })
        if (length < 0.2) return 0 to 0
        for (i in 0..2) right[i] /= length
        val yaw = (0..2).sumOf { rotation[it] * up[it] }
        val pitch = (0..2).sumOf { rotation[it] * right[it] }
        val rate = sqrt(yaw * yaw + pitch * pitch)
        if (rate <= deadZone) return 0 to 0
        // Slow turns are fine work, quick ones cross the glasses.
        val curve = (0.45 + 0.6 * rate).coerceIn(0.45, 1.7)
        val scale = gain * speed * curve * dt
        val mx = -yaw * scale + rx
        val my = -pitch * scale + ry
        val wx = mx.toLong().toDouble(); val wy = my.toLong().toDouble()
        rx = mx - wx; ry = my - wy
        return wx.toInt() to wy.toInt()
    }

    companion object {
        fun isDeliberate(rotation: FloatArray) = rotation.sumOf { (it * it).toDouble() } > 0.09
    }
}

class RemoteMotion(private val context: Context, private val onMove: (Int, Int, Boolean) -> Unit) : SensorEventListener {
    val air = AirPointer()
    private var running = false
    private val gravity = floatArrayOf(0f, 0f, 9.81f)
    private var last = 0L

    val isRunning get() = running

    fun start() {
        if (running) return
        val s = context.getSystemService(SensorManager::class.java) ?: return
        val gyro = s.getDefaultSensor(Sensor.TYPE_GYROSCOPE) ?: return
        running = true
        last = 0L
        s.registerListener(this, gyro, SensorManager.SENSOR_DELAY_GAME)
        s.getDefaultSensor(Sensor.TYPE_GRAVITY)?.let { s.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
    }

    fun stop() {
        if (!running) return
        running = false
        context.getSystemService(SensorManager::class.java)?.unregisterListener(this)
    }

    fun hold(seconds: Double) = air.hold(SystemClock.uptimeMillis() + (seconds * 1000).toLong())
    fun release() = air.release()

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_GRAVITY -> System.arraycopy(event.values, 0, gravity, 0, 3)
            Sensor.TYPE_GYROSCOPE -> {
                val t = event.timestamp
                val previous = last
                last = t
                if (previous == 0L) return
                val (dx, dy) = air.step(event.values, gravity, (t - previous) / 1e9, SystemClock.uptimeMillis())
                if (dx != 0 || dy != 0) onMove(dx, dy, AirPointer.isDeliberate(event.values))
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
