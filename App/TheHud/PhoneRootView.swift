import SwiftUI
import HudCore

/// The phone: icons and settings above, the surface on half the display pinned to the bottom
/// edge, and the system keyboard rising from the lower edge to push it all up.
struct PhoneRootView: View {
    @ObservedObject private var controller = HudController.shared
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HudToolBar().frame(height: PhoneMetrics.toolBar)

            // The slack. SwiftUI's keyboard avoidance takes the height it needs from here,
            // because everything else in the stack is fixed.
            SettingsArea()
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()

            surface.frame(height: PhoneMetrics.trackpad)
        }
        .background(.black)
        .overlay(alignment: .bottom) {
            // Invisible and off-screen, but focusable: the app draws no keyboard of its own, it
            // asks iOS for the real one. Autocorrect, dictation, swipe typing, every installed
            // language and the emoji picker all arrive with it.
            TextField("", text: .constant(""))
                .focused($typing)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }

    private var surface: some View {
        ZStack {
            HalftoneSurfaceView(config: controller.config,
                                contacts: controller.contacts,
                                surfaceSize: CGSize(width: PhoneMetrics.size.width,
                                                    height: PhoneMetrics.trackpad))

            TrackpadTouchHost(controller: controller)

            EdgeControlsOverlay(railActive: controller.rail.isActive)

            railHitRegion
            cornerHitRegion
        }
        .contentShape(Rectangle())
    }

    /// 52pt at the stored 1.32 scale, matching MiniMate's reserved region.
    private var railHitRegion: some View {
        Color.clear
            .frame(width: 52 * 1.32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if controller.rail.isActive {
                            controller.railMoved(to: value.location.y)
                        } else {
                            controller.railBegan(at: value.location.y)
                        }
                    }
                    .onEnded { _ in controller.railEnded() }
            )
    }

    /// 104pt at 1.28, opposite the rail.
    private var cornerHitRegion: some View {
        Color.clear
            .frame(width: 104 * 1.28, height: 104 * 1.28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .contentShape(Rectangle())
            .onTapGesture { controller.cornerTapped() }
    }
}
