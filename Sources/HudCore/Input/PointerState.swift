import Foundation
import CoreGraphics

/// Turns the recogniser's relative events into something the glasses canvas can draw.
///
/// MiniMate handed its deltas to a Bluetooth HID host, which owned the cursor. Nothing owns the
/// cursor here, so this does: it integrates the deltas, keeps the pointer on the canvas, and
/// tracks the button and scroll state the panels read.
public final class PointerState {
    public private(set) var position: CGPoint
    public private(set) var isDown = false
    public private(set) var isDragging = false
    /// Accumulated wheel ticks since the last read, positive meaning content moves up.
    public private(set) var scrollTicks: Int = 0
    public private(set) var lastClick: MouseButton?

    public var bounds: CGSize

    public init(bounds: CGSize = HudTheme.glassesSize, position: CGPoint? = nil) {
        self.bounds = bounds
        self.position = position ?? CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }

    public func apply(_ event: GestureEvent) {
        switch event {
        case let .move(dx, dy, dragging):
            position.x = min(max(position.x + CGFloat(dx), 0), bounds.width - 1)
            position.y = min(max(position.y + CGFloat(dy), 0), bounds.height - 1)
            isDragging = dragging

        case let .click(button, down):
            isDown = down
            if down { lastClick = button }

        case let .scroll(v, _):
            scrollTicks += v

        case .tapClick:
            lastClick = .left

        case .rightClick:
            lastClick = .right

        case .doubleTapDragStart:
            isDragging = true

        case .dragEnd:
            isDragging = false
            isDown = false

        case .scrollFling, .pinch:
            break
        }
    }

    public func drainScroll() -> Int {
        defer { scrollTicks = 0 }
        return scrollTicks
    }
}
