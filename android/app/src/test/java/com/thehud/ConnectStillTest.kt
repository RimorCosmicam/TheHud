package com.thehud

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.captureRoboImage
import com.thehud.phone.ConnectScreen
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Remote Connect's pairing screen, at the cover screen's size. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w412dp-h915dp-port-xxhdpi")
class ConnectStillTest {
    @get:Rule val compose = createComposeRule()

    @Test fun pairing() {
        HudController.connectLink = "thehud://connect?id=8bc0312a&k=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&h=192.168.1.20&p=47825"
        compose.setContent { ConnectScreen() }
        compose.onRoot().captureRoboImage("../../out/android/phone-connect.png")
    }
}
