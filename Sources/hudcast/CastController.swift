import AppKit
import ApplicationServices
import HudCore

/// Ties the pieces together and keeps the menu bar honest about what is happening.
///
/// The menu has the two choices: sharing on or off, and Mirror (the Mac's main screen) or Extend
/// (a screen of the glasses' own, above the main one, there only while a phone is connected).
@MainActor
final class CastController: NSObject, NSApplicationDelegate {
    enum Mode: String { case mirror, extend }

    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting\u{2026}", action: nil, keyEquivalent: "")
    private let shareItem = NSMenuItem(title: "", action: #selector(toggleSharing), keyEquivalent: "s")
    private let mirrorItem = NSMenuItem(title: "Mirror", action: #selector(chooseMirror), keyEquivalent: "m")
    private let extendItem = NSMenuItem(title: "Extend", action: #selector(chooseExtend), keyEquivalent: "e")
    private let accessLine = NSMenuItem(title: "Allow control of this Mac\u{2026}",
                                        action: #selector(openAccessibility), keyEquivalent: "")
    private var server: CastServer!
    private var capture: ScreenCapture!
    private let input = InputInjector()
    private var windowTimer: Timer?
    private var lastWindows: [DesktopWindow] = []
    private var connected = false
    private var virtualDisplay: VirtualDisplay?
    private var serverState = "Starting\u{2026}"

    private var sharing = UserDefaults.standard.object(forKey: "sharing") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sharing, forKey: "sharing") }
    }
    private var mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .mirror {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        for item in [shareItem, mirrorItem, extendItem] {
            item.target = self
            menu.addItem(item)
            if item === shareItem { menu.addItem(.separator()) }
        }
        menu.addItem(.separator())
        accessLine.target = self
        menu.addItem(accessLine)
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
            DispatchQueue.main.async {
                self?.serverState = text
                self?.refreshMenu()
            }
        }
        if sharing { server.start() }
        refreshMenu()
    }

    // ------------------------------------------------------------------ the menu

    private func refreshMenu() {
        shareItem.title = sharing ? "Stop Sharing" : "Start Sharing"
        mirrorItem.state = mode == .mirror ? .on : .off
        extendItem.state = mode == .extend ? .on : .off
        let what = mode == .mirror ? "mirroring this Mac" : "extending this Mac"
        statusLine.title = !sharing ? "Not sharing"
            : connected ? "Streaming to iPhone, \(what)" : serverState
        let symbol = connected ? "eyeglasses.circle.fill" : "eyeglasses"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "HudCast")
        statusItem.button?.appearsDisabled = !sharing
    }

    @objc private func toggleSharing() {
        sharing.toggle()
        if sharing {
            serverState = "Starting\u{2026}"
            server.start()
        } else {
            server.stop()
        }
        refreshMenu()
    }

    @objc private func chooseMirror() { choose(.mirror) }
    @objc private func chooseExtend() { choose(.extend) }

    private func choose(_ new: Mode) {
        guard new != mode else { return }
        mode = new
        refreshMenu()
        if connected { Task { await showScreen() } }
    }

    // ------------------------------------------------------------------ the phone

    private func phoneConnected() {
        connected = true
        lastWindows = []
        refreshMenu()
        Task {
            await showScreen()
            await sendWindows()
        }
        windowTimer?.invalidate()
        windowTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sendWindows() }
        }
        accessLine.isHidden = AXIsProcessTrusted()
    }

    private func phoneDisconnected() {
        connected = false
        windowTimer?.invalidate()
        refreshMenu()
        Task {
            await capture.stop()
            guard !connected else { return }   // a phone came straight back
            // Unplugged with the phone: macOS moves its windows back to the Mac's own screens.
            virtualDisplay = nil
            input.displayID = CGMainDisplayID()
        }
    }

    /// Streams the whole screen the mode asks for: the main one, or the glasses' own, plugged in
    /// above the main one first.
    private func showScreen() async {
        let id: CGDirectDisplayID
        if mode == .extend {
            if virtualDisplay == nil {
                virtualDisplay = VirtualDisplay()
                // A moment for macOS to lay the new screen out before it is moved.
                try? await Task.sleep(nanoseconds: 300_000_000)
                virtualDisplay?.placeAboveMain()
            }
            id = virtualDisplay?.id ?? CGMainDisplayID()
        } else {
            virtualDisplay = nil
            id = CGMainDisplayID()
        }
        capture.displayID = id
        input.displayID = id
        guard connected else { return }
        await capture.start(window: nil)
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
