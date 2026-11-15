package com.thehud

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.thehud.glasses.GlassesPresenter
import com.thehud.phone.CoverScreen

class HudApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        HudController.start(this)
    }
}

/** The phone's side: made for the cover screen, and it works on the inside screen too. */
class CoverActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // The cover screen sleeps after seconds; while it is the glasses' touchpad it should not.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent { CoverScreen() }
        if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION), 1)
        }
    }

    override fun onStart() {
        super.onStart()
        // The phone's own screens are never the glasses, whichever this activity is on.
        GlassesPresenter.start(this) { setOfNotNull(display?.displayId, 1) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        HudController.refreshWeather()
    }
}
