import Foundation
import CoreGraphics
import HudCore

// Ported from MiniMate's own unit tests, so a behavioural difference between the Kotlin engine
// and this one shows up here rather than in the hand.

func runFilterTests() {
    print("\nOneEuroFilter")

    test("smooths slow micro-vibrations") {
        let filter = OneEuroFilter(minCutoff: 1.0, beta: 0.0)
        var t = 0.0
        let value = 100.0
        _ = filter.filter(value, timestampMs: t)

        var outputs: [Double] = []
        for i in 1...20 {
            t += 16.66
            outputs.append(filter.filter(value + (i % 2 == 0 ? 2.0 : -2.0), timestampMs: t))
        }

        let maxDeviation = outputs.map { abs($0 - value) }.max() ?? 0
        expectLess(maxDeviation, 1.5, "finger tremor should not reach the cursor")
    }

    test("adapts quickly to rapid movement") {
        let filter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
        var t = 0.0
        _ = filter.filter(0, timestampMs: t)
        t += 16.66
        _ = filter.filter(500, timestampMs: t)
        t += 16.66
        expectGreater(filter.filter(1000, timestampMs: t), 800,
                      "a fast sweep must not lag behind the finger")
    }
}

func runAccelerationTests() {
    print("\nAccelerationCurve")

    test("zero movement returns zero") {
        let out = AccelerationCurve().process(dx: 0, dy: 0, dtMs: 16.6)
        expectEqual(out.dx, 0)
        expectEqual(out.dy, 0)
    }

    test("acceleration is non-linear in velocity") {
        let curve = AccelerationCurve()
        let slow = curve.process(dx: 2, dy: 0, dtMs: 16.6, trackingSpeed: 1.0, acceleration: 1.2)
        curve.reset()
        let fast = curve.process(dx: 20, dy: 0, dtMs: 16.6, trackingSpeed: 1.0, acceleration: 1.2)
        // Ten times the finger movement must buy more than ten times the pointer movement.
        expectGreater(fast.dx, slow.dx * 10)
    }

    test("subpixel carryover preserves fractional motion") {
        let curve = AccelerationCurve()
        let total = (0..<3).reduce(0) { sum, _ in
            sum + curve.process(dx: 0.6, dy: 0, dtMs: 16.6,
                                trackingSpeed: 1.0, acceleration: 0).dx
        }
        expect(total >= 1, "a slow drag must still move the pointer")
    }
}

func runImpulseTests() {
    print("\nTouchImpulseHistory")

    test("reused pointer id does not replace the previous reaction") {
        let history = TouchImpulseHistory()
        _ = history.update(active: [TouchPoint(x: 20, y: 30, id: 0)], now: 1)
        let released = history.update(active: [], now: 1.1)
        expectEqual(released.count, 1)

        let both = history.update(active: [TouchPoint(x: 200, y: 300, id: 0)], now: 1.2)
        expectEqual(both.count, 2)
        expect(!both[0].active, "the older impulse should be decaying")
        expect(both[1].active, "the new contact should be live")
        expectEqual(released[0].id, both[0].id)
        expect(both[0].id != both[1].id, "a reused pointer id must get a fresh impulse")
    }

    test("released reaction decays instead of persisting") {
        let history = TouchImpulseHistory()
        _ = history.update(active: [TouchPoint(x: 1, y: 2, id: 0)], now: 0)
        _ = history.update(active: [], now: 0.1)
        expectEqual(history.update(active: [], now: 1.0).count, 1, "decay still running")
        expectEqual(history.update(active: [], now: 3).count, 0, "decay finished")
        expectEqual(history.update(active: [], now: 200).count, 0)
    }

    test("oldest impulse is replaced at capacity") {
        let history = TouchImpulseHistory(capacity: 2)
        _ = history.update(active: [TouchPoint(x: 1, y: 2, id: 0)], now: 0)
        _ = history.update(active: [], now: 0.1)
        _ = history.update(active: [TouchPoint(x: 3, y: 4, id: 0)], now: 0.2)
        _ = history.update(active: [], now: 0.3)
        let newest = history.update(active: [TouchPoint(x: 5, y: 6, id: 0)], now: 0.4)

        expectEqual(newest.count, 2)
        expectEqual(newest[0].x, 3)
        expectEqual(newest[1].x, 5)
    }
}

func runMomentumTests() {
    print("\nMomentumScroller")

    test("slow release does not fling") {
        let scroller = MomentumScroller()
        expect(!scroller.startFling(velocityX: 10, velocityY: 40))
        expect(!scroller.isRunning)
    }

    test("fling decays and stops") {
        let scroller = MomentumScroller()
        expect(scroller.startFling(velocityX: 0, velocityY: 2000))

        var ticks = 0, frames = 0
        while scroller.isRunning && frames < 2000 {
            if let step = scroller.step() { ticks += abs(step.v) }
            frames += 1
        }

        expect(!scroller.isRunning, "friction must bring the fling to rest")
        expectGreater(ticks, 0, "a real fling must produce scroll")
        expectLess(frames, 2000, "the fling must terminate")
    }

    test("natural scrolling inverts the direction") {
        // The sub-pixel accumulator means a fling emits nothing for the first few frames: at
        // 4000px/s a 12ms frame is only 0.17 of a tick. Step until one actually lands.
        func firstTick(_ scroller: MomentumScroller) -> Int {
            for _ in 0..<200 where scroller.isRunning {
                if let step = scroller.step() { return step.v }
            }
            return 0
        }

        let natural = MomentumScroller()
        _ = natural.startFling(velocityX: 0, velocityY: 4000, isNatural: true)
        let inverted = MomentumScroller()
        _ = inverted.startFling(velocityX: 0, velocityY: 4000, isNatural: false)

        expectLess(firstTick(natural), 0)
        expectGreater(firstTick(inverted), 0)
    }
}

func runRailTests() {
    print("\nScrollRail")

    test("rail accumulates subpixel ticks") {
        let rail = ScrollRail()
        rail.begin(at: 0)
        // A 100pt sweep at 0.035 a point is 3.5 ticks: three now, half carried.
        expectEqual(rail.move(to: 100), -3)
        // Another 100pt completes the carried half.
        expectEqual(rail.move(to: 200), -4)
    }

    test("rail honours the scroll direction") {
        let rail = ScrollRail()
        rail.naturalScrolling = false
        rail.begin(at: 0)
        expectEqual(rail.move(to: 100), 3)
    }
}
