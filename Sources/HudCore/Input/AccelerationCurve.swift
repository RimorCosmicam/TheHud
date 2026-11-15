import Foundation

/// Calibrated trackpad acceleration curve.
///
/// Sub-pixel precision for micro-movements and smooth, controllable gain for larger swipes,
/// without the jumps a naive multiplier produces. The fractional remainder is carried between
/// calls, which is what lets a slow drag move the cursor at all.
public final class AccelerationCurve {
    public struct Output: Equatable, Sendable {
        public var dx: Int
        public var dy: Int
    }

    private var subpixelX: Float = 0
    private var subpixelY: Float = 0

    public init() {}

    /// - Parameters:
    ///   - dtMs: time since the previous sample, clamped to a sane frame range.
    ///   - trackingSpeed: base sensitivity, 0.4 to 2.5, calibrated at 1.0.
    ///   - acceleration: the power the speed factor is raised to.
    public func process(dx rawDx: Float, dy rawDy: Float, dtMs: Float,
                        trackingSpeed: Float = 1.0,
                        acceleration: Float = 1.15) -> Output {
        if rawDx == 0 && rawDy == 0 { return Output(dx: 0, dy: 0) }

        let safeDt = min(max(dtMs, 4), 33)
        let distance = (rawDx * rawDx + rawDy * rawDy).squareRoot()
        // Normalised per-frame speed on a 60fps baseline.
        let velocity = (distance / safeDt) * 16.67

        // 1.0x speed maps about one screen pixel to 0.75 canvas counts.
        let baseScale = 0.75 * trackingSpeed

        let gain: Float
        if acceleration > 0.01 && velocity > 1.2 {
            let speedFactor = min(max((velocity - 1.2) / 12, 0), 3.5)
            gain = 1.0 + pow(speedFactor, min(max(acceleration, 0.5), 1.8)) * 0.65
        } else {
            gain = 1.0
        }

        let multiplier = baseScale * gain
        let targetDx = rawDx * multiplier + subpixelX
        let targetDy = rawDy * multiplier + subpixelY

        let intDx = Int(targetDx)
        let intDy = Int(targetDy)

        subpixelX = targetDx - Float(intDx)
        subpixelY = targetDy - Float(intDy)

        return Output(dx: intDx, dy: intDy)
    }

    public func reset() {
        subpixelX = 0
        subpixelY = 0
    }
}
