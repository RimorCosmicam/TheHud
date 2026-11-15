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
            // Half the glass, unless the keyboard (with its predictive bar) leaves less than that
            // under the icon row. Then the surface gives up the difference rather than shoving
            // the icons under the Dynamic Island.
            let surfaceHeight = max(0, min(screenHeight / 2,
                                           geometry.size.height - PhoneMetrics.toolBar))

            VStack(spacing: 0) {
                HudToolBar(canGoBack: controller.snapshot.browser.canGoBack,
                           canGoForward: controller.snapshot.browser.canGoForward,
                           keyboardUp: controller.keyboardTarget != nil,
                           action: controller.perform)
                    .frame(height: PhoneMetrics.toolBar)

                // The slack. The keyboard takes the height it needs from here, because
                // everything else in the stack is fixed.
                SettingsArea(visible: controller.visible,
                             glassesConnected: controller.glassesConnected,
                             action: controller.perform)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()

                surface(CGSize(width: geometry.size.width, height: surfaceHeight))
            }
        }
        // Down to the glass at the bottom, so the surface's corners can follow the screen's.
        // Only the container edge is ignored: the keyboard still pushes everything up.
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) { keyboardProxy }
        .sheet(isPresented: $controller.showingSettings) {
            SettingsSheet(controller: controller)
                .presentationDetents([.medium, .large])
        }
        .preferredColorScheme(.dark)
        .onAppear { controller.start() }
        .onChange(of: controller.keyboardTarget) { _, target in typing = target != nil }
        .onChange(of: typing) { _, isTyping in
            if !isTyping, controller.keyboardTarget != nil { controller.endTyping() }
        }
    }

    /// Invisible but focusable: the app draws no keyboard of its own, it asks iOS for the real
    /// one. Autocorrect, dictation, swipe typing, every installed language and the emoji picker
    /// all arrive with it, and what is typed is forwarded to the address bar or the page.
    private var keyboardProxy: some View {
        TextField("", text: Binding(get: { controller.draft },
                                    set: { controller.draftChanged($0) }))
            .focused($typing)
            .keyboardType(controller.keyboardTarget == .address ? .webSearch : .default)
            .textInputAutocapitalization(controller.keyboardTarget == .address ? .never : .sentences)
            .autocorrectionDisabled(controller.keyboardTarget == .address)
            .submitLabel(controller.keyboardTarget == .address ? .go : .return)
            .onSubmit { controller.submitTyping() }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
    }

    private func surface(_ size: CGSize) -> some View {
        let keyboardUp = controller.keyboardTarget != nil
        return ZStack {
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
        .frame(height: size.height)
        .clipShape(PhoneMetrics.surfaceShape(keyboardUp: keyboardUp))
        .animation(.easeOut(duration: 0.2), value: keyboardUp)
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

                Section("Surface") {
                    Picker("Palette", selection: Binding(
                        get: { controller.config.colorway.label },
                        set: { label in
                            if let palette = HudController.palettes.first(where: { $0.label == label }) {
                                controller.config.colorway = palette
                            }
                        })) {
                        ForEach(HudController.palettes, id: \.label) { palette in
                            Text(palette.label).tag(palette.label)
                        }
                    }
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
        .onChange(of: controller.trackpad.trackingSpeed) { controller.settingsChanged() }
        .onChange(of: controller.trackpad.scrollSpeed) { controller.settingsChanged() }
        .onChange(of: controller.trackpad.naturalScrolling) { controller.settingsChanged() }
        .onChange(of: controller.trackpad.momentumScrolling) { controller.settingsChanged() }
        .onChange(of: controller.trackpad.tapToClick) { controller.settingsChanged() }
        .onChange(of: controller.config.colorway.label) { controller.settingsChanged() }
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
