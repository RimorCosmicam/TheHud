import Foundation
import CoreGraphics

/// The edge rail's scroll accumulator, from MiniMate's `EdgeControlsOverlay`.
///
/// Same 0.035 constant and same sub-pixel remainder as two-finger scroll, so sweeping the rail and
/// swiping two fingers move a page by the same amount for the same distance of thumb.
public final class ScrollRail {
    public var scrollSpeed: Float = 1.0
    public var naturalScrolling: Bool = true

    private var lastY: CGFloat = 0
    private var remainder: Float = 0
    public private(set) var isActive = false

    public init() {}

    public func begin(at y: CGFloat) {
        isActive = true
        lastY = y
        remainder = 0
    }

    /// - Returns: whole scroll ticks, or nil while the remainder is still filling.
    public func move(to y: CGFloat) -> Int? {
        guard isActive else { return nil }
        let rawDelta = Float(y - lastY)
        lastY = y
        let direction: Float = naturalScrolling ? -1 : 1
        let target = rawDelta * 0.035 * scrollSpeed * direction + remainder
        let ticks = Int(target)
        remainder = target - Float(ticks)
        return ticks == 0 ? nil : ticks
    }

    public func end() {
        isActive = false
        remainder = 0
    }
}
