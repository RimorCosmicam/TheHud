import SwiftUI
import Combine
import HudCore

/// The one piece of state both scenes read.
///
/// The phone scene owns the surface and the input; the glasses scene only draws. Keeping the
/// model here rather than in either scene is what lets the glasses come and go — unplugging the
/// cable tears down a scene, not the session.
@MainActor
final class HudController: ObservableObject {
    static let shared = HudController()

    @Published private(set) var snapshot = HudSnapshot(cursor: nil)
    @Published private(set) var contacts: [TouchPoint] = []
    @Published var mode: GlassesScreen.Mode = .browser
    @Published var config: HalftoneConfig = .miniMateDefault

    private let pointer = PointerState()
    private let momentum = MomentumScroller()
    private var momentumTimer: Timer?

    let rail = ScrollRail()
    private(set) lazy var recognizer: GestureRecognizer = {
        let recognizer = GestureRecognizer { [weak self] event in
            self?.handle(event)
        }
        recognizer.onTouchPointsUpdated = { [weak self] points in
            self?.contacts = points
        }
        return recognizer
    }()

    private init() {
        snapshot.cursor = pointer.position
    }

    func surfaceSizeChanged(to size: CGSize) {
        recognizer.surfaceSize = size
    }

    private func handle(_ event: GestureEvent) {
        pointer.apply(event)

        if case let .scrollFling(vx, vy) = event {
            startMomentum(vx: vx, vy: vy)
        } else if case .move = event {
            momentum.stop()
        }

        snapshot.cursor = pointer.position
    }

    /// MiniMate ran the fling on a coroutine. A timer is the same shape; the scroller itself is
    /// stepped explicitly either way, which is what makes it testable.
    private func startMomentum(vx: Float, vy: Float) {
        momentumTimer?.invalidate()
        guard momentum.startFling(velocityX: vx, velocityY: vy,
                                  friction: recognizer.settings.momentumFriction,
                                  scrollSpeed: recognizer.settings.scrollSpeed,
                                  isNatural: recognizer.settings.naturalScrolling)
        else { return }

        momentumTimer = Timer.scheduledTimer(withTimeInterval: MomentumScroller.frameInterval,
                                             repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                if let step = self.momentum.step() {
                    self.pointer.apply(.scroll(v: step.v, h: step.h))
                }
                if !self.momentum.isRunning { timer.invalidate() }
            }
        }
    }

    // The rail is outside the recogniser, exactly as it is in MiniMate: the pointer rejects edge
    // touches so the two never fight over the same thumb.
    func railBegan(at y: CGFloat) {
        momentum.stop()
        rail.begin(at: y)
    }

    func railMoved(to y: CGFloat) {
        if let ticks = rail.move(to: y) {
            pointer.apply(.scroll(v: ticks, h: 0))
        }
    }

    func railEnded() { rail.end() }

    func cornerTapped() { pointer.apply(.rightClick) }
}
