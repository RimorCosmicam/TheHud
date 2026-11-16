import SwiftUI
import HudCore

/// The phone: icons and settings above, the surface on half the display pinned to the bottom
/// edge, and the system keyboard rising from the lower edge to push it all up.
struct PhoneRootView: View {
    @ObservedObject private var controller = HudController.shared
    @FocusState private var typing: Bool
    /// The full display height, safe areas included: "half the screen" means half the glass.
    let screenHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let keyboardUp = controller.shownKeyboardTarget != nil
            // Working the Android phone's glasses, everything here is drawn from its state.
            let snapshot = controller.shownSnapshot
            let gap = keyboardUp ? PhoneMetrics.surfaceMargin : 0
            // A little over half the glass, unless the keyboard (with its predictive bar)
            // leaves less than that under the icon row. Then the surface gives up the
            // difference rather than shoving the icons under the Dynamic Island.
            let surfaceHeight = max(0, min((screenHeight * PhoneMetrics.trackpadFraction).rounded(),
                                           geometry.size.height - PhoneMetrics.toolBar - gap))

            VStack(spacing: 0) {
                HudToolBar(canGoBack: snapshot.browser.canGoBack,
                           canGoForward: snapshot.browser.canGoForward,
                           keyboardUp: keyboardUp,
                           isFavorite: snapshot.browser.isHome
                               ? nil : snapshot.browser.isFavorite,
                           action: controller.perform)
                    .frame(height: PhoneMetrics.toolBar)

                // The slack. The keyboard takes the height it needs from here, because
                // everything else in the stack is fixed.
                SettingsArea(arrangement: controller.shownArrangement,
                             solo: controller.shownSolo,
                             clearView: controller.shownClearView,
                             editing: controller.editingGlasses,
                             glassesConnected: controller.shownGlassesConnected,
                             tabs: snapshot.browser.tabs,
                             activeTab: snapshot.browser.activeTab,
                             desktop: snapshot.desktop,
                             showsWindows: controller.stripShowsWindows,
                             scenes: controller.shownScenes,
                             currentScene: controller.shownSceneIndex,
                             action: controller.perform)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()

                // Arranging the glasses, the editor has the trackpad's room.
                if !controller.editingGlasses {
                    surface(CGSize(width: geometry.size.width - PhoneMetrics.surfaceMargin * 2,
                                   height: surfaceHeight),
                            keyboardUp: keyboardUp)
                        .padding(.horizontal, PhoneMetrics.surfaceMargin)
                        .padding(.bottom, gap)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // The safe area is kept at the bottom on purpose: the pad ends above the home
        // indicator, where an upward swipe is iOS's and not ours.
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) { keyboardProxy }
        .overlay(alignment: .top) { recordingDot }
        .animation(.easeOut(duration: 0.25), value: controller.editingGlasses)
        .sheet(isPresented: $controller.showingSettings) {
            SettingsSheet(controller: controller)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $controller.showingRemoteConnect) {
            RemoteConnectView(controller: controller)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $controller.showingCaptionSessions) {
            NavigationStack { CaptionsSessionsView() }
                .presentationDetents([.medium, .large])
        }
        .preferredColorScheme(.dark)
        .onAppear { controller.start() }
        .onChange(of: controller.shownKeyboardTarget) { _, target in typing = target != nil }
        .onChange(of: typing) { _, isTyping in
            guard !isTyping else { return }
            // A tick later: Return on the Mac takes the focus back straight after the field
            // gives it up, and that should not count as putting the keyboard away.
            DispatchQueue.main.async {
                if !typing, controller.shownKeyboardTarget != nil { controller.endTyping() }
            }
        }
    }

    /// Captions are listening and saving: a red dot at the top of the phone, which only the
    /// wearer sees, the same place iOS puts its own.
    @ViewBuilder
    private var recordingDot: some View {
        if controller.snapshot.captions.isListening {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Text("CAPTIONS").font(HudTheme.mont(9, .black)).tracking(1.5)
                    .foregroundStyle(Color.red)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.black.opacity(0.8), in: Capsule())
            .padding(.top, 2)
            .allowsHitTesting(false)
        }
    }

    /// Invisible but focusable: the app draws no keyboard of its own, it asks iOS for the real
    /// one. Autocorrect, dictation, swipe typing, every installed language and the emoji picker
    /// all arrive with it, and what is typed is forwarded to the address bar or the page.
    private var keyboardProxy: some View {
        let target = controller.shownKeyboardTarget
        return TextField("", text: Binding(get: { controller.shownDraft },
                                    set: { controller.draftChanged($0) }))
            .focused($typing)
            .keyboardType(target == .page || target == .mac
                          || target == .note ? .default : .webSearch)
            .textInputAutocapitalization(target == .address ? .never : .sentences)
            .autocorrectionDisabled(target == .address)
            .submitLabel(target == .address ? .go
                         : target == .mapSearch || target == .youtubeSearch
                         ? .search : .return)
            .onSubmit {
                controller.submitTyping()
                if target == .mac { typing = true }
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }

    /// The header that switches it, then the pad: the trackpad, the remote, or the fullscreen
    /// app's own controls.
    private func surface(_ size: CGSize, keyboardUp: Bool) -> some View {
        let padSize = CGSize(width: size.width, height: max(size.height - PhoneMetrics.padHeader, 0))
        return VStack(spacing: 0) {
            PadHeader(current: controller.pad, app: controller.padApp, action: controller.perform)
            Group {
                switch controller.pad {
                case .touchpad: touchpad(padSize)
                case .remote: remote(padSize)
                case .app:
                    AppPad(kind: controller.padApp ?? .sky, snapshot: controller.shownSnapshot,
                           captionsLanguage: controller.captionsLanguage,
                           fullscreen: controller.shownSolo != nil, action: controller.perform)
                }
            }
            .frame(height: padSize.height)
            .clipShape(PhoneMetrics.surfaceShape(keyboardUp: keyboardUp))
            .animation(.easeOut(duration: 0.2), value: keyboardUp)
        }
        .frame(height: size.height)
    }

    private func touchpad(_ size: CGSize) -> some View {
        ZStack {
            HalftoneSurfaceView(config: controller.config,
                                contacts: controller.contacts,
                                surfaceSize: size)
                .allowsHitTesting(false)

            EdgeControlsOverlay(railActive: controller.railActive,
                                cornerPressed: controller.cornerPressed)
                .allowsHitTesting(false)

            // Last, so it is on top: every touch on the surface lands here and is sorted into
            // pad, rail or corner in UIKit.
            TrackpadTouchHost(controller: controller)
        }
    }

    /// Pointing the phone moves the cursor; the halftone shows through the zones.
    private func remote(_ size: CGSize) -> some View {
        ZStack {
            HalftoneSurfaceView(config: controller.config,
                                contacts: controller.contacts,
                                surfaceSize: size)
                .allowsHitTesting(false)
            RemotePad { zone, phase, point in
                controller.perform(.remote(zone, phase, point))
            }
        }
    }
}

/// Everything that is a setting rather than a control: how the pad feels, and how it looks.
struct SettingsSheet: View {
    @ObservedObject var controller: HudController

    var body: some View {
        NavigationStack {
            Form {
                Section("Trackpad") {
                    slider("Pointer speed", value: $controller.trackpad.trackingSpeed,
                           range: 0.4...2.5)
                    slider("Scroll speed", value: $controller.trackpad.scrollSpeed,
                           range: 0.4...2.5)
                    Toggle("Natural scrolling", isOn: $controller.trackpad.naturalScrolling)
                    Toggle("Momentum", isOn: $controller.trackpad.momentumScrolling)
                    Toggle("Tap to click", isOn: $controller.trackpad.tapToClick)
                }

                Section("Widgets") {
                    Picker("Captions language", selection: $controller.captionsLanguage) {
                        ForEach(CaptionsEngine.languages, id: \.id) { language in
                            Text(language.name).tag(language.id)
                        }
                    }
                    Stepper("Daily steps: \(controller.stepGoal.formatted())",
                            value: $controller.stepGoal, in: 2000...30000, step: 1000)
                    NavigationLink("Saved captions") { CaptionsSessionsView() }
                }

                Section {
                    Toggle("Show Subscriptions", isOn: $controller.youtubeSubscriptions)
                } header: {
                    Text("YouTube")
                } footer: {
                    Text("Adds your subscriptions feed next to Home and search.")
                }

                Section {
                    Toggle("Sound on this iPhone", isOn: $controller.hostSoundHere)
                } header: {
                    Text("Host mode")
                } footer: {
                    Text("YouTube's sound plays here, for headphones, instead of on the glasses. It keeps playing with the iPhone locked.")
                }

                Section {
                    ThemePicker(selection: $controller.themeColor)
                } header: {
                    Text("Theme")
                } footer: {
                    Text("\(controller.themeColor.title): the glasses, the phone, the touchpad and the app icon.")
                }

                Section("Surface") {
                    slider("Dot pitch", value: $controller.config.pitch, range: 12...40)
                    slider("Contrast", value: $controller.config.contrast, range: 0.2...1.0)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { controller.showingSettings = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(HudTheme.accent)
        .onChange(of: controller.trackpad.trackingSpeed) { controller.settingsChanged() }
        .onChange(of: controller.trackpad.scrollSpeed) { controller.settingsChanged() }
        .onChange(of: controller.trackpad.naturalScrolling) { controller.settingsChanged() }
        .onChange(of: controller.trackpad.momentumScrolling) { controller.settingsChanged() }
        .onChange(of: controller.trackpad.tapToClick) { controller.settingsChanged() }
        .onChange(of: controller.config.pitch) { controller.settingsChanged() }
        .onChange(of: controller.config.contrast) { controller.settingsChanged() }
    }

    private func slider(_ title: String, value: Binding<Float>,
                        range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

/// The eight theme colours as swatches, the chosen one ringed.
private struct ThemePicker: View {
    @Binding var selection: ThemeColor

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(ThemeColor.allCases) { theme in
                let chosen = theme == selection
                Button { selection = theme } label: {
                    VStack(spacing: 6) {
                        Circle().fill(theme.accent)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.85), lineWidth: chosen ? 3 : 0).padding(3))
                            .overlay(Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.black).opacity(chosen ? 1 : 0))
                        Text(theme.title).font(.caption2.weight(chosen ? .bold : .regular))
                            .foregroundStyle(chosen ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}
