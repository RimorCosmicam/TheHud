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
        window.rootViewController = UIHostingController(
            rootView: PhoneRootView(screenHeight: windowScene.screen.bounds.height))
        window.makeKeyAndVisible()
        self.window = window
        // Opened by scanning Remote Connect's code with the Camera app.
        if let url = options.urlContexts.first?.url { openRemoteLink(url) }
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        if let url = contexts.first?.url { openRemoteLink(url) }
    }

    private func openRemoteLink(_ url: URL) {
        MainActor.assumeIsolated {
            let controller = HudController.shared
            controller.showingRemoteConnect = true
            controller.pair(with: url.absoluteString)
        }
    }
}

/// The glasses. Draws only — every touch belongs to the phone.
///
/// NOTE ON iOS 27: several projects report that an app built *against the iOS 27 SDK* no longer
/// gets this scene from the Info.plist role alone and must also register a scene accessory
/// (`UIViewController.registerSceneAccessory(.externalNonInteractive(...))`).
///
/// That requirement is keyed to the SDK the app links against, not to the OS it runs on. CI
/// builds with Xcode 26.6 and the iOS 26.5 SDK — GitHub's runners have no Xcode 27 — so this app
/// gets the long-standing plist behaviour even on an iOS 27 device. Nothing to do here yet.
///
/// It becomes relevant the moment anyone builds this in Xcode 27. If the glasses start mirroring
/// the phone instead of showing this scene, that is the cause, and the registration above is the
/// fix — check its real signature against the SDK first, since the community reports conflict.
final class GlassesSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: GlassesHost())
        window.isHidden = false
        self.window = window
        HudController.shared.glassesConnected = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        HudController.shared.glassesConnected = false
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
            GlassesScreen(snapshot: controller.snapshot,
                          arrangement: controller.arrangement,
                          solo: controller.solo,
                          clearView: controller.clearView,
                          browserContent: AnyView(WebBrowserView(controller.browser)),
                          desktopContent: AnyView(DesktopVideoView(layer: controller.desktopLink.displayLayer)),
                          youtubeContent: AnyView(YouTubePlayerView(controller.youtubePlayer)),
                          mapGround: controller.mapGround,
                          artwork: controller.artwork,
                          photoImages: controller.photoImages,
                          placeholders: false,
                          liveGlass: true)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.black)
        .ignoresSafeArea()
        .statusBarHidden()
    }
}
