import Foundation
import CoreGraphics
import HudCore

// The glasses' grid: three widget slots down each side, one app in the centre, and the phone's
// miniature that arranges it all by dragging.

func runGridTests() {
    print("\nGrid")

    test("scenes: three presets, each widget once, nothing in a slot twice") {
        expectEqual(HudScene.presets.count, HudScene.count)
        for scene in HudScene.presets {
            let a = scene.arrangement
            for widgets in [(a.left + a.right).compactMap { $0 }, a.row.compactMap { $0 }] {
                expectEqual(Set(widgets).count, widgets.count)
                expect(!widgets.contains { $0 == a.centre?.kind }, "\(scene.name): the centre's app not a widget too")
            }
            expect(a.bigs.count <= 1, "\(scene.name): one app in the centre")
            let decoded = try? JSONDecoder().decode(HudScene.self, from: JSONEncoder().encode(scene))
            expectEqual(decoded, scene)
        }
        // DESK: the browser in the centre, the Mac a live widget beside the others.
        let desk = GlassesLayout(arrangement: HudScene.presets[0].arrangement)
        expectEqual(Set(desk.widgetFrames.map(\.kind)), [.clock, .calendar, .weather, .mac, .music, .note])
        expectEqual(desk.bigFrames.map(\.kind), [.browser])
        // STREET: one row along the top, the map under it, no columns.
        let street = GlassesLayout(arrangement: HudScene.presets[1].arrangement)
        expectEqual(street.widgetFrames.map(\.kind), [.clock, .weather, .calendar, .music])
        expect(Set(street.widgetFrames.map(\.frame.minY)).count == 1, "all in one row")
        expect(street.bigFrames.isEmpty, "no browser or Mac")
        expectEqual(street.centreApp?.kind, .map)
        expectEqual(street.centreApp?.frame, GlassesLayout.rowMain(along: .top))
    }

    test("row layout: four along an edge, one app in the rest, columns kept for coming back") {
        var a = HudScene.presets[0].arrangement   // DESK: the browser in the centre
        let columns = a
        a.setStrip(.bottom)
        let row = GlassesLayout(arrangement: a)
        expectEqual(row.widgetFrames.count, 4)
        let main = GlassesLayout.rowMain(along: .bottom)
        for (_, frame) in row.widgetFrames {
            expect(!frame.intersects(main), "widgets clear of the app")
            expectEqual(frame.maxY, GlassesLayout.safeFrame.maxY)
        }
        expectEqual(row.bigFrames.map(\.kind), [.browser])
        expectEqual(row.bigFrames.first?.frame, main)
        // Another app dropped in the middle takes the centre; the browser goes back to the icons.
        a.place(.note, at: .middle)
        let noted = GlassesLayout(arrangement: a)
        expect(noted.bigFrames.isEmpty, "the browser left")
        expectEqual(noted.centreApp?.kind, .note)
        expectEqual(noted.centreApp?.frame, main)
        // Widgets swap along the row; one from the drawer replaces what was there.
        let first = a.row[0]
        a.place(.captions, at: .row(0))
        expectEqual(a.row[0], .captions)
        expect(first.map { !a.isPlaced($0) } ?? true, "replaced one goes back to the icons")
        // A click lands on what is drawn there.
        let hit = GlassesLayout(arrangement: a).hitTest(CGPoint(x: GlassesLayout.rowFrame(0, along: .bottom).midX,
                                                                  y: GlassesLayout.rowFrame(0, along: .bottom).midY))
        if case let .widget(kind, _, _) = hit { expectEqual(kind, .captions) } else { expect(false, "\(hit)") }
        // Back to columns: as they were, but the note is the centre's now, not a widget too.
        a.setStrip(nil)
        expectEqual(a.left, columns.left)
        expectEqual(a.right, columns.right.map { $0 == .note ? nil : $0 })
        expectEqual(a.centre?.kind, .note)
        // Older saves have no row: they read as columns.
        let old = try! JSONSerialization.data(withJSONObject: ["left": ["clock"], "right": [], "bigs": [], "hidden": []])
        let decoded = try? JSONDecoder().decode(HudArrangement.self, from: old)
        expectEqual(decoded?.strip, nil)
        expectEqual(decoded?.row.count, HudArrangement.rowSlots)
    }

    test("the miniature's row: drops by column, the rest is the app") {
        let mini = MiniLayout(size: CGSize(width: 360, height: 104), strip: .top)
        expectEqual(mini.spot(at: CGPoint(x: 10, y: 5)), .row(0))
        expectEqual(mini.spot(at: CGPoint(x: 350, y: 5)), .row(3))
        expectEqual(mini.spot(at: CGPoint(x: 180, y: 90)), .middle)
        expect(!mini.rowSlot(0).intersects(mini.middle), "row clear of the app")
    }

    test("the browser dropped on a side in the miniature takes it over, and back") {
        let mini = MiniLayout(size: CGSize(width: 360, height: 104))
        var arrangement = HudArrangement.standard
        let left = mini.spot(at: CGPoint(x: 20, y: 50))
        expectEqual(left, .slot(.left, 1))
        arrangement.place(.browser, at: left)
        expectEqual(arrangement.takenSides, [.left])
        expectEqual(mini.bigFrames(arrangement).first?.frame.minX, 0)
        expect(GlassesLayout(arrangement: arrangement).widgetFrames.isEmpty, "left widgets covered")
        arrangement.place(.browser, at: mini.spot(at: CGPoint(x: 180, y: 50)))
        expectEqual(arrangement.takenSides, [])
        expectEqual(GlassesLayout(arrangement: arrangement).widgetFrames.count, 3)
    }

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

    test("place: any app in the middle is the centre's, swapping with the one there; off removes") {
        var arrangement = HudArrangement.standard
        arrangement.place(.note, at: .middle)
        expectEqual(arrangement.centre?.kind, .note)
        expect(!arrangement.isPlaced(.browser), "the browser, from nowhere, back to the icons")
        arrangement.place(.clock, at: .middle)
        expectEqual(arrangement.centre?.kind, .clock)
        expectEqual(arrangement.left, [.note, .weather, .map])
        arrangement.place(.weather, at: .off)
        expectEqual(arrangement.left, [.note, nil, .map])
    }

    test("place: the centre on a side reaches over it; any other app there is a widget") {
        var arrangement = HudArrangement.standard
        arrangement.place(.mac, at: .slot(.right, 2))
        expectEqual(arrangement.right, [nil, nil, .mac])
        expectEqual(arrangement.side(of: .mac), nil)
        arrangement.place(.browser, at: .slot(.right, 0))
        expectEqual(arrangement.side(of: .browser), .right)
        expectEqual(arrangement.takenSides, [.right])
        let layout = GlassesLayout(arrangement: arrangement)
        expectEqual(layout.bigFrames.last!.frame.maxX, GlassesLayout.safeFrame.maxX)
        expect(!layout.widgetFrames.contains { $0.kind == .mac }, "the Mac's widget is covered")
    }

    test("the app picker: a pick swaps the centre with the picked app's slot") {
        var arrangement = HudArrangement.standard
        arrangement.setCentre(.weather)
        expectEqual(arrangement.centre?.kind, .weather)
        expectEqual(arrangement.left, [.clock, .browser, .map])
        arrangement.setCentre(.browser)
        expectEqual(arrangement.left, [.clock, .weather, .map])
        // Picked while switched off, it comes back on.
        arrangement.toggleHidden(.browser)
        arrangement.setCentre(.browser)
        expect(arrangement.isShown(.browser))
        // The centre's app gets the centre's size and its clicks.
        arrangement.setCentre(.calendar)
        let layout = GlassesLayout(arrangement: arrangement)
        let frame = layout.centreApp!.frame
        expectEqual(frame, GlassesLayout.bigSpan(taking: []))
        expectEqual(layout.hitTest(CGPoint(x: frame.minX + 10, y: frame.minY + 20)),
                    .centre(.calendar, CGPoint(x: 10, y: 20), frame.size))
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
