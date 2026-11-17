import Foundation
import CoreGraphics
import HudCore

// The sky app's arithmetic, and pointing the phone as a remote.

func runSkyTests() {
    print("\nSky and remote")

    test("zodiac signs by ecliptic longitude, 30 degrees each, wrapping") {
        expectEqual(Zodiac(longitude: 0), .aries)
        expectEqual(Zodiac(longitude: 95), .cancer)
        expectEqual(Zodiac(longitude: 359.9), .pisces)
        expectEqual(Zodiac(longitude: -1), .pisces)
        expectEqual(Zodiac(longitude: 720 + 45), .taurus)
    }

    test("a plane straight overhead is at the zenith; one far off is low") {
        let above = SkyGeometry.look(fromLatitude: 38.7, longitude: -9.1, toLatitude: 38.7, longitude: -9.1,
                                     height: 10_000)
        expectGreater(above.alt, 89.9)
        expectLess(abs(above.distance - 10_000), 1)
        let east = SkyGeometry.look(fromLatitude: 38.7, longitude: -9.1, toLatitude: 38.7, longitude: -8.0,
                                    height: 10_000)
        expectLess(abs(east.az - 90), 2)
        expectLess(east.alt, 10)
        expectGreater(east.alt, 0)
    }

    test("looking round wraps; looking up stops at the horizon and short of the top") {
        var view = SkyView()
        view.look(pan: 200, tilt: -10)
        expectEqual(view.pan, -160)
        expectEqual(view.tilt, 0)
        view.look(pan: 0, tilt: 500)
        expectEqual(view.tilt, SkyView.tiltRange.upperBound)
        view.zoom(by: 100)
        expectEqual(view.fov, SkyView.fovRange.upperBound)
        view.zoom(by: 0)
        expectEqual(view.fov, SkyView.fovRange.upperBound)
        view.recentre()
        expect(!view.isAdjusted, "back to the usual view")
    }

    test("the Milky Way is there, as dots graded by level") {
        let sky = SkyModel.compute(at: Date(timeIntervalSince1970: 1_763_150_400), latitude: 38.7, longitude: -9.1)
        expect(!sky.milkyWay.isEmpty, "some of the galaxy is up")
        expect(sky.milkyWay.allSatisfy { (1...5).contains($0.level) }, "levels 1 to 5")
        expect(sky.milkyWay.allSatisfy { $0.points.allSatisfy { $0.alt > -3 } }, "none under the ground")
    }

    test("the remote: turning left moves left, tipping up moves up, a press holds it still") {
        var air = AirPointer()
        let flat = SIMD3<Double>(0, 0, -1)
        var left = (dx: 0, dy: 0)
        for i in 0..<10 {
            let s = air.step(rotation: SIMD3(0, 0, 1), gravity: flat, dt: 0.01, now: Double(i) * 0.01)
            left.dx += s.dx
            left.dy += s.dy
        }
        expectLess(left.dx, -10)
        expectEqual(left.dy, 0)

        var up = 0
        for i in 0..<10 {
            up += air.step(rotation: SIMD3(1, 0, 0), gravity: flat, dt: 0.01, now: Double(i) * 0.01).dy
        }
        expectLess(up, -10)

        // Held up in front of the face, turning still moves across.
        let upright = SIMD3<Double>(0, -1, 0)
        let across = air.step(rotation: SIMD3(0, 1, 0), gravity: upright, dt: 0.05, now: 1)
        expectLess(across.dx, 0)

        air.hold(until: 5)
        expectEqual(air.step(rotation: SIMD3(0, 0, 3), gravity: flat, dt: 0.01, now: 4.9).dx, 0)
        air.release()
        expect(air.step(rotation: SIMD3(0, 0, 3), gravity: flat, dt: 0.01, now: 4.9).dx != 0, "let go")

        // A hand at rest: under the dead zone, nothing.
        expectEqual(air.step(rotation: SIMD3(0.005, 0, 0.005), gravity: flat, dt: 0.01, now: 6).dx, 0)
        expect(!AirPointer.isDeliberate(SIMD3(0.05, 0.05, 0)), "tremor is not use")
    }

    test("the remote's zones tile the pad without overlapping") {
        let size = CGSize(width: 373, height: 443)
        let frames = RemoteZone.allCases.map { RemotePadLayout.frame($0, in: size) }
        for (i, a) in frames.enumerated() {
            expect(CGRect(origin: .zero, size: size).contains(a), "inside the pad")
            for b in frames[(i + 1)...] { expect(!a.intersects(b), "\(a) and \(b) overlap") }
        }
        expectLess(abs(frames[0].width - frames[2].width), 0.01)
    }

    test("timer presets start over; more time only on a countdown") {
        var timer = HudTimer(setSeconds: 300)
        timer.toggle(at: Date())
        timer.set(minutes: 25)
        expectEqual(timer.setSeconds, 1500)
        expect(timer.isIdle, "a preset starts over")
        timer.add(minutes: 1)
        expectEqual(timer.setSeconds, 1560)
        timer.set(minutes: 0)
        timer.add(minutes: 5)
        expectEqual(timer.setSeconds, 0)
    }

    test("apps with their own phone controls") {
        expectEqual(Set(HudPanelKind.allCases.filter(\.hasPhoneControls)), [.sky, .music, .clock, .captions, .note, .youtube, .prompter, .photos, .camera, .books])
    }
}
