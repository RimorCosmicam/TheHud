import AppKit
import HudCore

// HudCast: the Mac side of TheHud's desktop panel. A menu bar app with no window: it advertises
// itself on the local network, and while a phone is connected it streams the screen and takes
// the phone's input.

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = CastController()
    app.delegate = controller
    withExtendedLifetime(controller) { app.run() }
}
