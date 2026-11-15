import Foundation
import CoreGraphics
import HudCore

/// The state machine, driven frame by frame. None of this needs a device, which is the whole
/// reason the recogniser takes `TouchFrame` rather than `UITouch`.
final class Harness {
    var events: [GestureEvent] = []
    let recognizer: GestureRecognizer

    init() {
        var sink: (GestureEvent) -> Void = { _ in }
        recognizer = GestureRecognizer { sink($0) }
        // The surface is half an iPhone 15 Pro display.
        recognizer.surfaceSize = CGSize(width: 393, height: 426)
        sink = { [weak self] in self?.events.append($0) }
        recognizer.onGesture = sink
    }

    func point(_ x: CGFloat, _ y: CGFloat, id: Int = 0) -> TouchPoint {
        TouchPoint(x: x, y: y, id: id)
    }

    func send(_ action: TouchAction, _ touches: [TouchPoint],
              at timeMs: Double, actionIndex: Int = 0,
              history: [CoalescedSample] = []) {
        recognizer.handle(TouchFrame(action: action, touches: touches,
                                     actionIndex: actionIndex, timeMs: timeMs,
                                     history: history))
    }

    var moves: [GestureEvent] {
        events.filter { if case .move = $0 { return true }; return false }
    }
}

func runGestureTests() {
    print("\nGestureRecognizer \u{2014} taps")

    test("a quick tap clicks") {
        let h = Harness()
        h.send(.down, [h.point(200, 300)], at: 0)
        h.send(.up, [h.point(200, 300)], at: 100)
        expectEqual(h.events, [.tapClick])
    }

    test("a slow press does not click") {
        let h = Harness()
        h.send(.down, [h.point(200, 300)], at: 0)
        h.send(.up, [h.point(200, 300)], at: 400)   // past the 220ms tap timeout
        expect(h.events.isEmpty, "a long press is not a click")
    }

    test("a tap that moved too far does not click") {
        let h = Harness()
        h.send(.down, [h.point(200, 300)], at: 0)
        h.send(.move, [h.point(240, 300)], at: 16)
        h.send(.up, [h.point(240, 300)], at: 100)
        expect(!h.events.contains(.tapClick))
    }

    print("\nGestureRecognizer \u{2014} edges")

    test("an edge sweep belongs to the rail, not the pointer") {
        let h = Harness()
        h.send(.down, [h.point(4, 300)], at: 0)
        h.send(.move, [h.point(4, 360)], at: 16)
        h.send(.up, [h.point(4, 360)], at: 100)
        expect(h.events.isEmpty, "the rail and corner own the edges")
    }

    test("a touch just inside the margin is accepted") {
        let h = Harness()
        h.send(.down, [h.point(20, 300)], at: 0)
        h.send(.up, [h.point(20, 300)], at: 100)
        expectEqual(h.events, [.tapClick])
    }

    print("\nGestureRecognizer \u{2014} pointer")

    test("movement emits pointer deltas") {
        let h = Harness()
        h.send(.down, [h.point(100, 200)], at: 0)
        h.send(.move, [h.point(140, 200)], at: 16)

        guard case let .move(dx, dy, dragging)? = h.events.first else {
            return expect(false, "expected a move, got \(h.events)")
        }
        expectGreater(dx, 0)
        expectEqual(dy, 0)
        expect(!dragging)
    }

    test("coalesced samples are consumed") {
        let h = Harness()
        h.send(.down, [h.point(100, 200)], at: 0)
        // One frame carrying three intermediate samples, as a 120Hz digitiser delivers to a
        // 60Hz runloop. Dropping these is what makes fast motion feel stepped.
        h.send(.move, [h.point(160, 200)], at: 16, history: [
            CoalescedSample(timeMs: 4, touches: [h.point(120, 200)]),
            CoalescedSample(timeMs: 8, touches: [h.point(135, 200)]),
            CoalescedSample(timeMs: 12, touches: [h.point(148, 200)]),
        ])
        expectEqual(h.moves.count, 4, "three coalesced samples plus the frame's own")
    }

    print("\nGestureRecognizer \u{2014} two fingers")

    test("a two-finger tap is a right click") {
        let h = Harness()
        h.send(.down, [h.point(100, 200)], at: 0)
        h.send(.pointerDown, [h.point(100, 200), h.point(160, 200, id: 1)], at: 10)
        h.send(.pointerUp, [h.point(100, 200), h.point(160, 200, id: 1)], at: 100, actionIndex: 1)
        expectEqual(h.events, [.rightClick])
    }

    test("a two-finger drag scrolls") {
        let h = Harness()
        h.send(.down, [h.point(100, 200)], at: 0)
        h.send(.pointerDown, [h.point(100, 200), h.point(160, 200, id: 1)], at: 10)
        // Crossing the slop arms scrolling; it must not also emit a tick.
        h.send(.move, [h.point(100, 250), h.point(160, 250, id: 1)], at: 26)
        expect(h.events.isEmpty, "crossing the slop arms scrolling rather than scrolling")

        h.send(.move, [h.point(100, 300), h.point(160, 300, id: 1)], at: 42)
        guard case let .scroll(v, hor)? = h.events.first else {
            return expect(false, "expected a scroll, got \(h.events)")
        }
        // Natural scrolling is on by default, so a downward sweep scrolls up.
        expectLess(v, 0)
        expectEqual(hor, 0)
    }

    test("releasing a moving scroll hands off to momentum") {
        let h = Harness()
        h.send(.down, [h.point(100, 200)], at: 0)
        h.send(.pointerDown, [h.point(100, 200), h.point(160, 200, id: 1)], at: 10)
        h.send(.move, [h.point(100, 250), h.point(160, 250, id: 1)], at: 26)
        h.send(.move, [h.point(100, 330), h.point(160, 330, id: 1)], at: 42)
        h.send(.pointerUp, [h.point(100, 330), h.point(160, 330, id: 1)], at: 58, actionIndex: 1)

        expect(h.events.contains { if case .scrollFling = $0 { return true }; return false },
               "a moving release must fling")
    }

    test("a second finger suppresses the pointer until release") {
        let h = Harness()
        h.send(.down, [h.point(100, 200)], at: 0)
        h.send(.pointerDown, [h.point(100, 200), h.point(160, 200, id: 1)], at: 10)
        h.send(.pointerUp, [h.point(100, 200), h.point(160, 200, id: 1)], at: 20, actionIndex: 1)
        h.events.removeAll()

        // One finger is still down, but it must not become a pointer mid-gesture.
        h.send(.move, [h.point(200, 200)], at: 30)
        expect(h.events.isEmpty, "the remaining finger must not jump the cursor")
    }

    print("\nGestureRecognizer \u{2014} drag")

    test("double-tap drag presses only once the finger moves") {
        let h = Harness()
        h.send(.down, [h.point(200, 300)], at: 0)
        h.send(.up, [h.point(200, 300)], at: 80)
        expectEqual(h.events, [.tapClick])
        h.events.removeAll()

        // Second tap inside the double-tap window: armed, but nothing pressed yet, so an
        // ordinary double-click still works if the finger simply lifts.
        h.send(.down, [h.point(201, 301)], at: 160)
        expect(h.events.isEmpty, "arming must not press the button")

        h.send(.move, [h.point(240, 340)], at: 180)
        expectEqual(h.events.first, .click(button: .left, down: true))
        expect(h.events.contains(.doubleTapDragStart))

        h.events.removeAll()
        h.send(.up, [h.point(240, 340)], at: 300)
        expectEqual(h.events, [.click(button: .left, down: false), .dragEnd])
    }

    test("a cancelled drag releases the button") {
        let h = Harness()
        h.send(.down, [h.point(200, 300)], at: 0)
        h.send(.up, [h.point(200, 300)], at: 80)
        h.send(.down, [h.point(201, 301)], at: 160)
        h.send(.move, [h.point(240, 340)], at: 180)
        h.events.removeAll()

        h.send(.cancel, [h.point(240, 340)], at: 200)
        expectEqual(h.events, [.click(button: .left, down: false), .dragEnd],
                    "a cancelled drag must not leave the button stuck down")
    }

    print("\nPointerState")

    test("the cursor integrates deltas and stays on the canvas") {
        let pointer = PointerState(bounds: CGSize(width: 1920, height: 1080),
                                   position: CGPoint(x: 10, y: 10))
        pointer.apply(.move(dx: -100, dy: -100, isDragging: false))
        expectEqual(pointer.position, CGPoint(x: 0, y: 0))

        pointer.apply(.move(dx: 5000, dy: 5000, isDragging: false))
        expectEqual(pointer.position, CGPoint(x: 1919, y: 1079))
    }
}
