import Foundation

/// 1€ Filter (Casiez et al., CHI 2012) for low-latency, jitter-free pointer tracking.
///
/// Adjusts the cutoff by instantaneous velocity: low cutoff at rest removes digitiser jitter and
/// finger tremor, high cutoff at speed removes the phase lag, so the cursor stays 1:1 with the
/// hand instead of trailing it.
public final class OneEuroFilter {
    private let minCutoff: Double
    private let beta: Double
    private let dCutoff: Double

    private var xPrev: Double = 0
    private var dxPrev: Double = 0
    private var tPrev: Double = -1

    public init(minCutoff: Double = 1.2, beta: Double = 0.05, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private func alpha(rate: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        let te = 1.0 / rate
        return 1.0 / (1.0 + tau / te)
    }

    public func filter(_ value: Double, timestampMs: Double) -> Double {
        if tPrev < 0 {
            xPrev = value
            dxPrev = 0
            tPrev = timestampMs
            return value
        }

        let dt = (timestampMs - tPrev) / 1000.0
        tPrev = timestampMs
        if dt <= 0 { return xPrev }

        let rate = 1.0 / dt

        let dx = (value - xPrev) * rate
        let aD = alpha(rate: rate, cutoff: dCutoff)
        let dxHat = aD * dx + (1.0 - aD) * dxPrev
        dxPrev = dxHat

        let cutoff = minCutoff + beta * abs(dxHat)
        let a = alpha(rate: rate, cutoff: cutoff)
        let xHat = a * value + (1.0 - a) * xPrev
        xPrev = xHat
        return xHat
    }

    public func reset() {
        tPrev = -1
        xPrev = 0
        dxPrev = 0
    }
}
