import Foundation
import CoreGraphics

/// How the phone's surface works: as a trackpad, or as a remote that is pointed.
public enum PointerMode: String, CaseIterable, Sendable {
    case touchpad, remote

    public var title: String {
        switch self {
        case .touchpad: "TOUCHPAD"
        case .remote: "REMOTE"
        }
    }
}

/// Pointing with the phone, the way an air mouse does: turning it left or right moves the cursor
/// across, tipping its top edge up or down moves it up or down.
///
/// It works from the gyroscope's turning rate rather than from where the phone points, so there
/// is no calibration and no drift to fight; where the cursor ends up is wherever the hand took
/// it, and the CENTRE zone puts it back. The turn is measured about the room's vertical and about
/// the phone's own left-right edge laid level, so it reads the same flat in the hand or tipped
/// towards the face.
public struct AirPointer: Sendable {
    /// Cursor pixels per radian of turn at a middling speed. 2,200 puts the glasses' width in
    /// about fifty degrees of wrist.
    public var gain: Double = 2200
    public var speed: Double = 1
    /// Below this the hand is holding still and the gyro's last whisper is ignored.
    public var deadZone: Double = 0.02

    private var remainder = SIMD2<Double>(0, 0)
    private var heldUntil: TimeInterval = 0

    public init() {}

    /// Holds the cursor still for a moment: pressing a zone with the thumb shakes the phone, and
    /// a click should land where it was aimed.
    public mutating func hold(until time: TimeInterval) {
        heldUntil = max(heldUntil, time)
        remainder = .zero
    }

    /// Lets go of a hold early, as when a thumb leaves the scroll strip.
    public mutating func release() {
        heldUntil = 0
        remainder = .zero
    }

    /// - Parameters:
    ///   - rotation: turning rate in the phone's frame, radians a second (x right, y up the
    ///     screen, z out of it).
    ///   - gravity: gravity in the same frame.
    /// - Returns: whole pixels to move, keeping the fraction for next time.
    public mutating func step(rotation: SIMD3<Double>, gravity: SIMD3<Double>, dt: Double,
                              now: TimeInterval) -> (dx: Int, dy: Int) {
        guard dt > 0, dt < 0.2, now >= heldUntil else { return (0, 0) }
        let g = (gravity * gravity).sum().squareRoot()
        guard g > 0.1 else { return (0, 0) }
        let up = -gravity / g
        // The phone's left-right edge, laid level.
        var right = SIMD3<Double>(1, 0, 0) - up * up.x
        let length = (right * right).sum().squareRoot()
        guard length > 0.2 else { return (0, 0) }
        right /= length

        let yaw = (rotation * up).sum()      // turning left is positive
        let pitch = (rotation * right).sum() // tipping the top up is positive
        let rate = (yaw * yaw + pitch * pitch).squareRoot()
        guard rate > deadZone else { return (0, 0) }

        // Slow turns are fine work, quick ones cross the glasses.
        let curve = min(max(0.45 + 0.6 * rate, 0.45), 1.7)
        let scale = gain * speed * curve * dt
        let move = SIMD2(-yaw * scale, -pitch * scale) + remainder
        let whole = SIMD2(move.x.rounded(.towardZero), move.y.rounded(.towardZero))
        remainder = move - whole
        return (Int(whole.x), Int(whole.y))
    }

    /// A turn quick enough to count as someone using it, for keeping the cursor awake. A hand
    /// at rest or a phone in a pocket stays under it.
    public static func isDeliberate(_ rotation: SIMD3<Double>) -> Bool {
        (rotation * rotation).sum() > 0.3 * 0.3
    }
}
