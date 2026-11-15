import Foundation
import CoreGraphics

/// One contact, in the trackpad's own coordinate space (points).
public struct TouchPoint: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var id: Int
    public var pressure: CGFloat
    public var startedAtSeconds: Double
    public var active: Bool

    public init(x: CGFloat, y: CGFloat, id: Int, pressure: CGFloat = 1,
                startedAtSeconds: Double = 0, active: Bool = true) {
        self.x = x
        self.y = y
        self.id = id
        self.pressure = pressure
        self.startedAtSeconds = startedAtSeconds
        self.active = active
    }
}

public enum MouseButton: Sendable { case left, right }

/// What the recogniser emits. MiniMate turned these into Bluetooth HID reports for a Mac; here
/// they drive a cursor inside the app's own glasses canvas, so there is no pairing, no companion
/// and no HID layer at all.
public enum GestureEvent: Equatable, Sendable {
    case move(dx: Int, dy: Int, isDragging: Bool)
    case click(button: MouseButton, down: Bool)
    case scroll(v: Int, h: Int)
    case scrollFling(velocityX: Float, velocityY: Float)
    case pinch(scale: Float)
    case tapClick
    case rightClick
    case doubleTapDragStart
    case dragEnd
}

/// The subset of MiniMate's settings the engine reads, with its stored defaults.
public struct TouchpadSettings: Sendable {
    public var trackingSpeed: Float = 1.0
    public var acceleration: Float = 1.15
    public var scrollSpeed: Float = 1.0
    public var naturalScrolling: Bool = true
    public var invertCursorY: Bool = false
    public var momentumScrolling: Bool = true
    public var momentumFriction: Float = 0.92
    public var tapToClick: Bool = true
    public var twoFingerRightClick: Bool = true
    public var doubleTapDrag: Bool = true
    public var edgeMargin: CGFloat = 12

    /// Android reads this from `ViewConfiguration.scaledTouchSlop`, which is about 8dp. UIKit has
    /// no equivalent constant, so the number is carried over directly as points.
    public var touchSlop: CGFloat = 8

    public init() {}
}

/// How a frame of touches arrived. Mirrors `MotionEvent`'s masked actions, because the state
/// machine below is built around that shape and rewriting it to UIKit's phases would be a
/// rewrite of the logic rather than a port of it.
public enum TouchAction: Sendable {
    case down          // the first finger
    case pointerDown   // an additional finger
    case move
    case pointerUp     // one finger lifted, others still down
    case up            // the last finger lifted
    case cancel
}

/// One delivery of touches.
///
/// `history` carries the samples that arrived between this frame and the previous one. Android
/// calls them historical events and UIKit calls them coalesced touches; both exist because the
/// digitiser samples faster than the screen refreshes, and consuming them is most of why pointer
/// motion feels attached to the finger rather than to the frame clock.
public struct CoalescedSample: Sendable {
    public var timeMs: Double
    public var touches: [TouchPoint]

    public init(timeMs: Double, touches: [TouchPoint]) {
        self.timeMs = timeMs
        self.touches = touches
    }
}

public struct TouchFrame: Sendable {
    public var action: TouchAction
    /// Every pointer currently down, stable in index order. On `pointerUp` the lifting pointer is
    /// still present, at `actionIndex`.
    public var touches: [TouchPoint]
    public var actionIndex: Int
    /// Milliseconds, on any monotonic clock.
    public var timeMs: Double
    public var history: [CoalescedSample]

    public init(action: TouchAction, touches: [TouchPoint], actionIndex: Int = 0,
                timeMs: Double, history: [CoalescedSample] = []) {
        self.action = action
        self.touches = touches
        self.actionIndex = actionIndex
        self.timeMs = timeMs
        self.history = history
    }

    var pointerCount: Int { touches.count }
}
