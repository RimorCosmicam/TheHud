import Foundation
import CoreGraphics

/// High-precision gesture recognition with sub-pixel accumulation, ported from MiniMate.
///
/// Deliberately free of UIKit: it consumes `TouchFrame` values and emits `GestureEvent`s, so the
/// whole state machine runs under `swift test` on a Mac. The UIKit layer is a thin adapter that
/// turns touches and their coalesced samples into frames.
public final class GestureRecognizer {
    public var settings = TouchpadSettings()
    /// The trackpad's own size, for edge rejection.
    public var surfaceSize: CGSize = .zero

    public var onGesture: (GestureEvent) -> Void
    public var onTouchPointsUpdated: (([TouchPoint]) -> Void)?

    private let tapTimeout: Double = 220
    private let doubleTapTimeout: Double = 300
    private var touchSlop: CGFloat { settings.touchSlop }

    private let filterDx = OneEuroFilter(minCutoff: 1.5, beta: 0.08)
    private let filterDy = OneEuroFilter(minCutoff: 1.5, beta: 0.08)
    private let accelerationCurve = AccelerationCurve()

    // One-finger state
    private var downTime1: Double = 0
    private var downX1: CGFloat = 0
    private var downY1: CGFloat = 0
    private var lastX1: CGFloat = 0
    private var lastY1: CGFloat = 0
    private var lastTime1: Double = 0
    private var totalMoved1: CGFloat = 0
    private var isDragging = false
    private var dragArmed = false
    private var gestureAccepted = false
    private var suppressSingleFingerUntilUp = false
    private var lastTapUpTime: Double = 0
    private var lastTapPoint: CGPoint?

    // Two-finger state
    private var downTime2: Double = 0
    private var downAvg: CGPoint = .zero
    private var lastAvg: CGPoint = .zero
    private var lastTime2: Double = 0
    private var totalMoved2: CGFloat = 0
    private var initialPinchSpan: CGFloat = 0
    private var isTwoFingerGestureActive = false
    private var isScrollingTwoFinger = false
    private var didScrollTwoFinger = false
    private var scrollVelocityX: Float = 0
    private var scrollVelocityY: Float = 0

    private var subpixelScrollX: Float = 0
    private var subpixelScrollY: Float = 0

    public private(set) var activeTouchPoints: [TouchPoint] = []

    public init(onGesture: @escaping (GestureEvent) -> Void) {
        self.onGesture = onGesture
    }

    public func handle(_ frame: TouchFrame) {
        updateActiveTouchPoints(frame)

        switch frame.action {
        case .down: handleDown(frame)
        case .pointerDown: handlePointerDown(frame)
        case .move: handleMove(frame)
        case .pointerUp: handlePointerUp(frame)
        case .up: handleUp(frame)
        case .cancel: handleCancel()
        }
    }

    private func updateActiveTouchPoints(_ frame: TouchFrame) {
        activeTouchPoints.removeAll(keepingCapacity: true)
        if frame.action != .up && frame.action != .cancel {
            for (index, touch) in frame.touches.enumerated() {
                // The pointer that is lifting is not a live contact any more.
                if frame.action == .pointerUp && index == frame.actionIndex { continue }
                activeTouchPoints.append(touch)
            }
        }
        onTouchPointsUpdated?(activeTouchPoints)
    }

    /// The rail and the corner own the edges, so the pointer must not also claim them.
    private func isEdgeTouch(_ point: CGPoint) -> Bool {
        let margin = settings.edgeMargin
        guard surfaceSize.width > margin * 2, surfaceSize.height > margin * 2 else { return false }
        return point.x < margin || point.x > surfaceSize.width - margin
            || point.y < margin || point.y > surfaceSize.height - margin
    }

    private func handleDown(_ frame: TouchFrame) {
        guard let touch = frame.touches.first else { return }
        let point = CGPoint(x: touch.x, y: touch.y)

        gestureAccepted = !isEdgeTouch(point)
        suppressSingleFingerUntilUp = false
        dragArmed = false
        guard gestureAccepted else { return }

        downX1 = point.x
        downY1 = point.y
        lastX1 = point.x
        lastY1 = point.y
        lastTime1 = frame.timeMs
        downTime1 = frame.timeMs
        totalMoved1 = 0

        filterDx.reset()
        filterDy.reset()
        accelerationCurve.reset()

        // Arm on the second tap, but do not press the button until the finger moves, so an
        // ordinary double-click still happens when the second tap is simply released.
        if settings.doubleTapDrag, let lastTap = lastTapPoint {
            let elapsed = frame.timeMs - lastTapUpTime
            let distance = hypot(point.x - lastTap.x, point.y - lastTap.y)
            dragArmed = elapsed >= 1 && elapsed < doubleTapTimeout && distance < touchSlop * 2
        }
    }

    private func handlePointerDown(_ frame: TouchFrame) {
        guard gestureAccepted else { return }
        if frame.pointerCount > 2 {
            isTwoFingerGestureActive = false
            isScrollingTwoFinger = false
            suppressSingleFingerUntilUp = true
            return
        }
        guard frame.pointerCount == 2 else { return }

        if isDragging {
            onGesture(.click(button: .left, down: false))
            onGesture(.dragEnd)
            isDragging = false
        }
        dragArmed = false
        isTwoFingerGestureActive = true
        suppressSingleFingerUntilUp = true
        downTime2 = frame.timeMs

        let a = frame.touches[0], b = frame.touches[1]
        downAvg = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        lastAvg = downAvg
        lastTime2 = downTime2
        totalMoved2 = 0
        isScrollingTwoFinger = false
        didScrollTwoFinger = false
        scrollVelocityX = 0
        scrollVelocityY = 0
        initialPinchSpan = hypot(a.x - b.x, a.y - b.y)
        subpixelScrollX = 0
        subpixelScrollY = 0
    }

    private func handleMove(_ frame: TouchFrame) {
        guard gestureAccepted else { return }

        if frame.pointerCount == 1 && !isTwoFingerGestureActive && !suppressSingleFingerUntilUp {
            // Coalesced samples first, then the frame's own, exactly as the historical events are
            // drained on Android. Dropping them makes fast motion feel stepped.
            for sample in frame.history where !sample.touches.isEmpty {
                step1Finger(x: sample.touches[0].x, y: sample.touches[0].y, timeMs: sample.timeMs)
            }
            if let touch = frame.touches.first {
                step1Finger(x: touch.x, y: touch.y, timeMs: frame.timeMs)
            }
        } else if frame.pointerCount >= 2 {
            for sample in frame.history where sample.touches.count >= 2 {
                step2Finger(sample.touches[0], sample.touches[1], timeMs: sample.timeMs)
            }
            if frame.touches.count >= 2 {
                step2Finger(frame.touches[0], frame.touches[1], timeMs: frame.timeMs)
            }
        }
    }

    private func step1Finger(x rawX: CGFloat, y rawY: CGFloat, timeMs: Double) {
        let dt = Float(max(timeMs - lastTime1, 1))
        let rawDx = rawX - lastX1
        let rawDy = rawY - lastY1

        totalMoved1 = max(totalMoved1, hypot(rawX - downX1, rawY - downY1))
        lastX1 = rawX
        lastY1 = rawY
        lastTime1 = timeMs

        if rawDx == 0 && rawDy == 0 { return }

        if dragArmed && totalMoved1 >= touchSlop {
            dragArmed = false
            isDragging = true
            onGesture(.click(button: .left, down: true))
            onGesture(.doubleTapDragStart)
        }

        let smoothDx = Float(filterDx.filter(Double(rawDx), timestampMs: timeMs))
        let smoothDy = Float(filterDy.filter(Double(rawDy), timestampMs: timeMs))
        let adjustedDy = settings.invertCursorY ? -smoothDy : smoothDy

        let output = accelerationCurve.process(dx: smoothDx, dy: adjustedDy, dtMs: dt,
                                               trackingSpeed: settings.trackingSpeed,
                                               acceleration: settings.acceleration)
        if output.dx != 0 || output.dy != 0 {
            onGesture(.move(dx: output.dx, dy: output.dy, isDragging: isDragging))
        }
    }

    private func step2Finger(_ a: TouchPoint, _ b: TouchPoint, timeMs: Double) {
        let avg = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let rawDx = avg.x - lastAvg.x
        let rawDy = avg.y - lastAvg.y
        let dtSeconds = Float(max(timeMs - lastTime2, 1)) / 1000

        totalMoved2 = max(totalMoved2, hypot(avg.x - downAvg.x, avg.y - downAvg.y))
        lastAvg = avg
        lastTime2 = timeMs

        if rawDx == 0 && rawDy == 0 { return }

        // A centroid threshold, so two resting fingers cannot accumulate wheel ticks out of
        // digitiser noise alone.
        if !isScrollingTwoFinger {
            if totalMoved2 < touchSlop { return }
            isScrollingTwoFinger = true
            subpixelScrollX = 0
            subpixelScrollY = 0
            scrollVelocityX = 0
            scrollVelocityY = 0
            return
        }

        scrollVelocityX = scrollVelocityX * 0.65 + (Float(rawDx) / dtSeconds) * 0.35
        scrollVelocityY = scrollVelocityY * 0.65 + (Float(rawDy) / dtSeconds) * 0.35

        // Natural scrolling affects two-finger scroll only, never the pointer.
        let scrollSign: Float = settings.naturalScrolling ? -1 : 1

        let targetV = Float(rawDy) * 0.035 * settings.scrollSpeed * scrollSign + subpixelScrollY
        let targetH = Float(rawDx) * 0.035 * settings.scrollSpeed * scrollSign + subpixelScrollX

        let intV = Int(targetV)
        let intH = Int(targetH)
        subpixelScrollY = targetV - Float(intV)
        subpixelScrollX = targetH - Float(intH)

        if intV != 0 || intH != 0 {
            didScrollTwoFinger = true
            onGesture(.scroll(v: intV, h: intH))
        }

        let span = hypot(a.x - b.x, a.y - b.y)
        if initialPinchSpan > 0 && abs(span - initialPinchSpan) > touchSlop * 3 {
            onGesture(.pinch(scale: Float(span / initialPinchSpan)))
        }
    }

    private func handlePointerUp(_ frame: TouchFrame) {
        guard gestureAccepted else { return }
        guard frame.pointerCount == 2 && isTwoFingerGestureActive else { return }

        let duration = frame.timeMs - downTime2
        if totalMoved2 < touchSlop && duration < tapTimeout && settings.twoFingerRightClick {
            onGesture(.rightClick)
        } else if didScrollTwoFinger && settings.momentumScrolling {
            onGesture(.scrollFling(velocityX: scrollVelocityX, velocityY: scrollVelocityY))
        }

        isTwoFingerGestureActive = false
        isScrollingTwoFinger = false
        subpixelScrollX = 0
        subpixelScrollY = 0
    }

    private func handleUp(_ frame: TouchFrame) {
        guard gestureAccepted else {
            resetState()
            return
        }

        let now = frame.timeMs
        let duration = now - downTime1

        if isDragging {
            isDragging = false
            onGesture(.click(button: .left, down: false))
            onGesture(.dragEnd)
        } else if !suppressSingleFingerUntilUp && totalMoved1 < touchSlop
                    && duration < tapTimeout && settings.tapToClick {
            onGesture(.tapClick)
            lastTapUpTime = now
            lastTapPoint = frame.touches.first.map { CGPoint(x: $0.x, y: $0.y) }
        } else if !dragArmed {
            lastTapUpTime = 0
            lastTapPoint = nil
        }

        resetState()
    }

    private func handleCancel() {
        if isDragging {
            onGesture(.click(button: .left, down: false))
            onGesture(.dragEnd)
            isDragging = false
        }
        resetState()
    }

    private func resetState() {
        downX1 = 0
        downY1 = 0
        lastX1 = 0
        lastY1 = 0
        totalMoved1 = 0
        gestureAccepted = false
        suppressSingleFingerUntilUp = false
        dragArmed = false
        isTwoFingerGestureActive = false
        isScrollingTwoFinger = false
        subpixelScrollX = 0
        subpixelScrollY = 0
        filterDx.reset()
        filterDy.reset()
        accelerationCurve.reset()
    }
}
