import AppKit
import ApplicationServices
import HudCore

/// Ties the pieces together and keeps the menu bar honest about what is happening.
@MainActor
final class CastController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting\u{2026}", action: nil, keyEquivalent: "")
    private let accessLine = NSMenuItem(title: "Allow control of this Mac\u{2026}",
                                        action: #selector(openAccessibility), keyEquivalent: "")
    private var server: CastServer!
    private var capture: ScreenCapture!
    private let input = InputInjector()
    private var windowTimer: Timer?
    private var lastWindows: [DesktopWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eyeglasses",
                                           accessibilityDescription: "HudCast")
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        accessLine.target = self
        menu.addItem(accessLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit HudCast", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu

        // Input from the phone is posted as real events, which needs Accessibility. Ask once;
        // the stream works without it, the clicks do not.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        accessLine.isHidden = AXIsProcessTrustedWithOptions(options)

        capture = ScreenCapture { [weak self] keyframe, avcc, sps, pps in
            self?.server.sendFrame(keyframe: keyframe, avcc: avcc, sps: sps, pps: pps)
        }
        capture.onSource = { [weak self] source in
            DispatchQueue.main.async {
                self?.input.source = source
                self?.server.send(.source, json: source)
            }
        }
        capture.isBusy = { [weak self] in self?.server.isBackedUp ?? false }

        server = CastServer()
        server.onConnect = { [weak self] in
            DispatchQueue.main.async { self?.phoneConnected() }
        }
        server.onDisconnect = { [weak self] in
            DispatchQueue.main.async { self?.phoneDisconnected() }
        }
        server.onCommand = { [weak self] command in
            DispatchQueue.main.async { self?.handle(command) }
        }
        server.onState = { [weak self] text in
            DispatchQueue.main.async { self?.statusLine.title = text }
        }
        server.start()
    }

    private func phoneConnected() {
        statusLine.title = "Streaming to iPhone"
        statusItem.button?.image = NSImage(systemSymbolName: "eyeglasses.circle.fill",
                                           accessibilityDescription: "HudCast, streaming")
        lastWindows = []
        Task {
            await sendWindows()
            await capture.start(window: input.source?.window)
        }
        windowTimer?.invalidate()
        windowTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sendWindows() }
        }
        accessLine.isHidden = AXIsProcessTrusted()
    }

    private func phoneDisconnected() {
        statusLine.title = "Waiting for iPhone"
        statusItem.button?.image = NSImage(systemSymbolName: "eyeglasses",
                                           accessibilityDescription: "HudCast")
        windowTimer?.invalidate()
        Task { await capture.stop() }
    }

    private func sendWindows() async {
        let windows = await capture.windows()
        guard windows != lastWindows else { return }
        lastWindows = windows
        server.send(.windows, json: windows)
    }

    private func handle(_ command: DesktopCommand) {
        if case let .select(window) = command {
            Task { await capture.start(window: window) }
            return
        }
        input.perform(command)
    }

    @objc private func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
