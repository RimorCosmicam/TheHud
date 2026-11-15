import CoreMotion
import HudCore

/// The gyroscope, for pointing the phone like a remote. Runs only while REMOTE is the pad and the
/// phone is in use; the turning it reads becomes cursor movement through `AirPointer`.
@MainActor
final class RemoteMotion {
    private let manager = CMMotionManager()
    private var lastTime: TimeInterval?
    var air = AirPointer()
    /// Whole pixels to move, and whether the turn was a deliberate one.
    var onMove: ((Int, Int, Bool) -> Void)?

    var isRunning: Bool { manager.isDeviceMotionActive }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        lastTime = nil
        manager.deviceMotionUpdateInterval = 1.0 / 100
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.take(motion) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lastTime = nil
    }

    /// Keeps the cursor still while a thumb presses: see `AirPointer.hold(until:)`.
    func hold(for seconds: TimeInterval) {
        air.hold(until: ProcessInfo.processInfo.systemUptime + seconds)
    }

    func release() { air.release() }

    private func take(_ motion: CMDeviceMotion) {
        defer { lastTime = motion.timestamp }
        guard let last = lastTime else { return }
        let r = motion.rotationRate, g = motion.gravity
        let rotation = SIMD3(r.x, r.y, r.z)
        let step = air.step(rotation: rotation, gravity: SIMD3(g.x, g.y, g.z),
                            dt: motion.timestamp - last, now: ProcessInfo.processInfo.systemUptime)
        if step.dx != 0 || step.dy != 0 {
            onMove?(step.dx, step.dy, AirPointer.isDeliberate(rotation))
        }
    }
}
