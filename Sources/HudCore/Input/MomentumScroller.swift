import Foundation

/// Kinetic momentum scrolling, after the Magic Trackpad's inertial deceleration.
///
/// MiniMate ran this on a coroutine with a 12ms delay. Here it is stepped explicitly so it can be
/// driven by a display link on the device and by a loop in a test on a Mac, and so a fling's whole
/// trajectory can be asserted rather than observed.
public final class MomentumScroller {
    /// About 83Hz, which is what MiniMate's 12ms delay came to.
    public static let frameInterval: Double = 0.012
    private static let minVelocity: Float = 15
    private static let launchThreshold: Float = 50

    private var vx: Float = 0
    private var vy: Float = 0
    private var sign: Float = 1
    private var friction: Float = 0.92
    private var subpixelV: Float = 0
    private var subpixelH: Float = 0

    public private(set) var isRunning = false

    public init() {}

    /// - Returns: whether the fling was fast enough to start at all.
    @discardableResult
    public func startFling(velocityX: Float, velocityY: Float,
                           friction: Float = 0.92,
                           scrollSpeed: Float = 1.0,
                           isNatural: Bool = true) -> Bool {
        stop()
        guard abs(velocityY) >= Self.launchThreshold
                || abs(velocityX) >= Self.launchThreshold else { return false }

        vx = velocityX * scrollSpeed
        vy = velocityY * scrollSpeed
        self.friction = friction
        sign = isNatural ? -1 : 1
        isRunning = true
        return true
    }

    /// Advances one frame. Returns a step only when the accumulator has crossed a whole tick.
    public func step(dt: Double = MomentumScroller.frameInterval) -> (v: Int, h: Int)? {
        guard isRunning else { return nil }
        guard abs(vx) > Self.minVelocity || abs(vy) > Self.minVelocity else {
            stop()
            return nil
        }

        let dtf = Float(dt)
        let stepY = vy * dtf * 0.0035 * sign + subpixelV
        let stepX = vx * dtf * 0.0035 * sign + subpixelH

        let intY = Int(stepY)
        let intX = Int(stepX)
        subpixelV = stepY - Float(intY)
        subpixelH = stepX - Float(intX)

        let decay = pow(friction, dtf * 60)
        vx *= decay
        vy *= decay

        return (intY == 0 && intX == 0) ? nil : (v: intY, h: intX)
    }

    public func stop() {
        isRunning = false
        vx = 0
        vy = 0
        subpixelV = 0
        subpixelH = 0
    }
}
