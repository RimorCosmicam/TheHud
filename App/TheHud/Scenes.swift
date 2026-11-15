import UIKit
import SwiftUI
import HudCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // The glasses arrive as a second scene in the non-interactive external display role. The
        // phone keeps its own scene, which is what lets the phone show a controller instead of a
        // mirror of the canvas.
        if session.role == .windowExternalDisplayNonInteractive {
            let configuration = UISceneConfiguration(name: "Glasses", sessionRole: session.role)
            configuration.delegateClass = GlassesSceneDelegate.self
            return configuration
        }

        let configuration = UISceneConfiguration(name: "Phone", sessionRole: session.role)
        configuration.delegateClass = PhoneSceneDelegate.self
        return configuration
    }
}

final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: PhoneRootView())
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// The glasses. Draws only — every touch belongs to the phone.
///
/// NOTE ON iOS 27: several projects report that an app built against the iOS 27 SDK no longer
/// gets this scene from the Info.plist role alone and must also register a scene accessory
/// (`UIViewController.registerSceneAccessory(.externalNonInteractive(...))`). Reports conflict on
/// whether it is mandatory, and the exact signature has not been checked against the real SDK, so
/// it is deliberately not called here: the plist role is long-standing API and gives a build that
/// compiles. If the glasses mirror the phone instead of showing this scene, that registration is
/// the first thing to add.
final class GlassesSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: GlassesHost())
        window.isHidden = false
        self.window = window
    }
}

/// Scales the fixed 1920x1080 canvas to whatever the glasses actually report.
struct GlassesHost: View {
    @ObservedObject private var controller = HudController.shared

    var body: some View {
        GeometryReader { geometry in
            let canvas = HudTheme.glassesSize
            let scale = min(geometry.size.width / canvas.width,
                            geometry.size.height / canvas.height)
            GlassesScreen(snapshot: controller.snapshot, mode: controller.mode)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.black)
        .ignoresSafeArea()
        .statusBarHidden()
    }
}
