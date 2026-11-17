package com.thehud

import android.Manifest
import android.accounts.AccountManager
import android.app.Application
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
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
    private val chooseAccount = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        result.data?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)?.let { HudController.webSignIn(this, it) }
    }

    /** Picks one of the phone's Google accounts (Android asks the wearer) to sign the glasses' browser in. */
    fun signInWithGoogle() {
        chooseAccount.launch(AccountManager.newChooseAccountIntent(null, null, arrayOf("com.google"), null, null, null, null))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // The cover screen sleeps after seconds; while it is the glasses' touchpad it should not.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent { CoverScreen() }
        // Everything the panels read, asked for once; each panel says what it lacks if refused.
        val wanted = arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA, Manifest.permission.ACTIVITY_RECOGNITION, Manifest.permission.READ_CALENDAR,
            Manifest.permission.POST_NOTIFICATIONS,
            if (android.os.Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE)
        val missing = wanted.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 1)
    }

    override fun onStart() {
        super.onStart()
        // The phone's own screens are never the glasses, whichever this activity is on.
        GlassesPresenter.start(this) { setOfNotNull(display?.displayId, 1) }
        HudController.appInFront(true)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        HudController.refreshWeather()
        HudController.startProviders()
    }

    override fun onStop() {
        super.onStop()
        HudController.appInFront(false)
        // Out of the app: the launcher icon can take the theme colour now.
        HudController.applyThemeIcon()
    }

    override fun onResume() {
        super.onResume()
        // Back from the system's settings (notification access, accessibility): pick up what changed.
        HudController.startProviders()
    }
}
