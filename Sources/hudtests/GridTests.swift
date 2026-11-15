import Foundation
import CoreGraphics
import HudCore

// The glasses' grid: three widget slots down each side, the browser and the Mac in the middle,
// and the phone's miniature that arranges it all by dragging.

func runGridTests() {
    print("\nGrid")

    test("slots: three down each side, the same size, inside the safe inset") {
        let safe = GlassesLayout.safeFrame
        for side in HudSide.allCases {
            let top = GlassesLayout.slotFrame(side, 0), bottom = GlassesLayout.slotFrame(side, 2)
            expectEqual(top.minY, safe.minY)
            expect(abs(bottom.maxY - safe.maxY) < 0.001, "bottom slot ends at the inset")
            expectEqual(top.width, GlassesLayout.slotWidth)
        }
        expectEqual(GlassesLayout.slotFrame(.right, 0).maxX, safe.maxX)
    }

    test("a click on a widget is a point inside it") {
        let layout = GlassesLayout()
        let clock = GlassesLayout.slotFrame(.left, 0)
        expectEqual(layout.hitTest(CGPoint(x: clock.minX + 10, y: clock.minY + 20)),
                    .widget(.clock, CGPoint(x: 10, y: 20), clock.size))
    }

    test("hidden widgets keep their slot but are not drawn") {
        var arrangement = HudArrangement.standard
        arrangement.toggleHidden(.weather)
        expectEqual(arrangement.spot(of: .weather), .slot(.left, 1))
        let kinds = GlassesLayout(arrangement: arrangement).widgetFrames.map(\.kind)
        expectEqual(kinds, [.clock, .map])
        arrangement.toggleHidden(.weather)
        expectEqual(GlassesLayout(arrangement: arrangement).widgetFrames.count, 3)
    }

    test("clear view: nothing drawn and nothing clicked") {
        let layout = GlassesLayout(arrangement: .standard, clearView: true)
        expect(layout.widgetFrames.isEmpty && layout.bigFrames.isEmpty)
        expectEqual(layout.hitTest(CGPoint(x: 960, y: 540)), .none)
    }

    test("a held widget is its app: every click goes to it") {
        let layout = GlassesLayout(arrangement: .standard, solo: .clock)
        expectEqual(layout.hitTest(CGPoint(x: 100, y: 100)),
                    .widget(.clock, CGPoint(x: 36, y: 36), GlassesLayout.safeFrame.size))
    }

    test("place: a widget onto a taken slot swaps with it") {
        var arrangement = HudArrangement.standard
        arrangement.place(.map, at: .slot(.left, 0))
        expectEqual(arrangement.left, [.map, .weather, .clock])
    }

    test("place: a new widget onto a taken slot sends the old one back to the icons") {
        var arrangement = HudArrangement.standard
        arrangement.place(.music, at: .slot(.left, 1))
        expectEqual(arrangement.left, [.clock, .music, .map])
        expect(!arrangement.isPlaced(.weather))
        expect(arrangement.unplaced.contains(.weather))
    }

    test("place: widgets never take the middle; off removes") {
        var arrangement = HudArrangement.standard
        arrangement.place(.note, at: .middle)
        expect(!arrangement.isPlaced(.note))
        arrangement.place(.clock, at: .off)
        expectEqual(arrangement.left, [nil, .weather, .map])
    }

    test("place: a big panel on a side reaches over it; the other big one gives that side up") {
        var arrangement = HudArrangement.standard
        arrangement.place(.mac, at: .slot(.right, 2))
        expectEqual(arrangement.side(of: .mac), .right)
        arrangement.place(.browser, at: .slot(.right, 0))
        expectEqual(arrangement.side(of: .browser), .right)
        expectEqual(arrangement.side(of: .mac), nil)
        // Left to right: the Mac in the middle, the browser reaching right.
        expectEqual(arrangement.orderedBigs.map(\.kind), [.mac, .browser])
        let frames = GlassesLayout(arrangement: arrangement).bigFrames
        expectEqual(frames.last!.frame.maxX, GlassesLayout.safeFrame.maxX)
    }

    test("arrangement survives saving") {
        var arrangement = HudArrangement.standard
        arrangement.place(.sky, at: .slot(.right, 1))
        arrangement.toggleHidden(.map)
        let data = try! JSONEncoder().encode(arrangement)
        expectEqual(try? JSONDecoder().decode(HudArrangement.self, from: data), arrangement)
    }

    test("miniature: drops land on the slot or the middle under the finger") {
        let mini = MiniLayout(size: CGSize(width: 360, height: 104))
        let slot = mini.slot(.right, 2)
        expectEqual(mini.spot(at: CGPoint(x: slot.midX, y: slot.midY)), .slot(.right, 2))
        expectEqual(mini.spot(at: CGPoint(x: 180, y: 50)), .middle)
        expectEqual(mini.spot(at: CGPoint(x: 5, y: 0)), .slot(.left, 0))
        expect(mini.middle.minX > mini.slot(.left, 0).maxX)
    }

    print("\nTimer")

    let start = Date(timeIntervalSince1970: 1_000_000)

    test("timer counts down, pauses and finishes") {
        var timer = HudTimer(setSeconds: 60)
        expectEqual(timer.reading(at: start).text, "1:00")
        timer.toggle(at: start)
        expectEqual(timer.reading(at: start.addingTimeInterval(20.4)).text, "0:40")
        timer.toggle(at: start.addingTimeInterval(30))
        expectEqual(timer.reading(at: start.addingTimeInterval(500)).state, .paused)
        timer.toggle(at: start.addingTimeInterval(500))
        let done = timer.reading(at: start.addingTimeInterval(531))
        expectEqual(done.state, .done)
        expectEqual(done.text, "0:00")
    }

    test("the wheel sets an idle timer in minutes, then fives past ten") {
        var timer = HudTimer(setSeconds: 300)
        timer.adjust(notches: 3)
        expectEqual(timer.setSeconds, 480)
        timer.adjust(notches: 3)
        expectEqual(timer.setSeconds, 15 * 60)
        timer.toggle(at: start)
        timer.adjust(notches: 5)
        expectEqual(timer.setSeconds, 15 * 60)
    }

    test("set to zero it is a stopwatch") {
        var timer = HudTimer(setSeconds: 60)
        timer.adjust(notches: -1)
        expectEqual(timer.setSeconds, 0)
        timer.toggle(at: start)
        let reading = timer.reading(at: start.addingTimeInterval(75))
        expect(reading.isStopwatch && reading.progress == nil)
        expectEqual(reading.text, "1:15")
        expectEqual(reading.state, .running)
    }

    print("\nSky")

    test("Lisbon in mid-November: sunrise before eight, sunset before six, stars at night") {
        let lisbon = TimeZone(identifier: "Europe/Lisbon")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = lisbon
        let night = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 22))!
        let sky = SkyModel.compute(at: night, latitude: 38.72, longitude: -9.14, timeZone: lisbon,
                                   locale: Locale(identifier: "en_GB"))
        expectEqual(sky.sunrise?.hasPrefix("07:"), true)
        expectEqual(sky.sunset?.hasPrefix("17:"), true)
        expect(sky.dayProgress == nil, "night")
        expect(sky.sunAltitude < -30, "the sun is well down: \(sky.sunAltitude)")
        expect(sky.stars.count > 800, "\(sky.stars.count) stars up")
        expect(!sky.lines.isEmpty && !sky.constellations.isEmpty)
        expect(sky.bodies.contains { $0.kind == .moon })
    }

    test("moon phases by angle") {
        expectEqual(SkyModel.moonPhase(0).name, "NEW MOON")
        expectEqual(SkyModel.moonPhase(92).name, "FIRST QUARTER")
        expectEqual(SkyModel.moonPhase(181).symbol, "moonphase.full.moon")
        expectEqual(SkyModel.moonPhase(350).name, "NEW MOON")
    }

    print("\nAir")

    test("air quality: index, UV and the strongest pollen; missing pollen drops out") {
        let json = """
        {"current":{"time":"2026-11-15T15:00","european_aqi":47,"pm2_5":12.5,"uv_index":6.2,
        "grass_pollen":34.0,"birch_pollen":2.0,"olive_pollen":null}}
        """
        let air = try! AirQualityProvider.decode(Data(json.utf8))
        expectEqual(air.index, 47)
        expectEqual(air.label, "MODERATE")
        expectEqual(air.uvLabel, "HIGH")
        expectEqual(air.pollen, "GRASS \u{00B7} MODERATE")
        let none = try! AirQualityProvider.decode(Data(#"{"current":{"european_aqi":10,"uv_index":0}}"#.utf8))
        expect(none.pollen == nil)
    }
}
