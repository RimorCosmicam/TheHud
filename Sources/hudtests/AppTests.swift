import Foundation
import CoreGraphics
import CoreLocation
import HudCore

// The solo apps: the Maps app's controls and directions, the forecast, the clock's other places.

func runAppTests() {
    print("\nApps")

    test("maps: search field, then each result row below it, in order") {
        let layout = MapsLayout(resultCount: 3)
        expectEqual(layout.hitTest(CGPoint(x: layout.searchFrame.midX, y: layout.searchFrame.midY)),
                    .search)
        for index in 0..<3 {
            let row = layout.resultFrame(index)
            expectEqual(layout.hitTest(CGPoint(x: row.midX, y: row.midY)), .result(index))
        }
        // A row that is not drawn is not hit.
        let missing = layout.resultFrame(3)
        expectEqual(layout.hitTest(CGPoint(x: missing.midX, y: missing.midY)), .none)
    }

    test("maps: while navigating the search is gone and the trip buttons work") {
        let layout = MapsLayout(resultCount: 0, navigating: true)
        expectEqual(layout.hitTest(CGPoint(x: layout.searchFrame.midX, y: layout.searchFrame.midY)),
                    .none)
        expectEqual(layout.hitTest(CGPoint(x: layout.endFrame.midX, y: layout.endFrame.midY)),
                    .endRoute)
        expectEqual(layout.hitTest(CGPoint(x: layout.transportFrame.midX,
                                           y: layout.transportFrame.midY)), .transport)
    }

    test("maps: zoom buttons on the right edge, inside the panel") {
        let layout = MapsLayout()
        expectEqual(layout.hitTest(CGPoint(x: layout.zoomInFrame.midX, y: layout.zoomInFrame.midY)),
                    .zoomIn)
        expectEqual(layout.hitTest(CGPoint(x: layout.zoomOutFrame.midX,
                                           y: layout.zoomOutFrame.midY)), .zoomOut)
        expect(layout.panel.contains(layout.zoomOutFrame))
        expect(!layout.zoomInFrame.intersects(layout.zoomOutFrame))
    }

    test("navigation: turns are taken as they are reached, and the distance counts down") {
        // Three points 100 m apart going north: start, turn, destination.
        let start = CLLocationCoordinate2D(latitude: 38.7, longitude: -9.13)
        let degree = 100 / 111_320.0
        let turn = CLLocationCoordinate2D(latitude: 38.7 + degree, longitude: -9.13)
        let end = CLLocationCoordinate2D(latitude: 38.7 + degree * 2, longitude: -9.13)
        let plan = RoutePlan(destination: "Miradouro", points: [start, turn, end],
                             steps: [.init(instruction: "", point: start, distance: 100),
                                     .init(instruction: "Turn right onto Rua A", point: turn,
                                           distance: 100),
                                     .init(instruction: "Arrive at the destination", point: end,
                                           distance: 0)],
                             expectedTravelTime: 150, distance: 200)
        var tracker = NavigationTracker(plan: plan)
        var nav = tracker.update(at: start)
        expectEqual(nav.instruction, "Turn right onto Rua A")
        expectEqual(nav.maneuver, "arrow.turn.up.right")
        expectEqual(nav.stepDistance, "100 M")
        expectEqual(nav.remainingDistance, "200 M")

        nav = tracker.update(at: turn)
        expectEqual(nav.maneuver, "mappin.and.ellipse")
        expect(!nav.arrived)

        nav = tracker.update(at: end)
        expect(nav.arrived)
        expectEqual(nav.instruction, "You have arrived")
    }

    test("navigation: turn arrows from English and Portuguese instructions") {
        expectEqual(NavigationTracker.maneuverSymbol("Vire à esquerda na Rua X"), "arrow.turn.up.left")
        expectEqual(NavigationTracker.maneuverSymbol("Keep slight right"), "arrow.up.right")
        expectEqual(NavigationTracker.maneuverSymbol("Continue onto Av. Brasil"), "arrow.up")
        expectEqual(NavigationTracker.maneuverSymbol("Na rotatória, pegue a 2ª saída"),
                    "arrow.triangle.turn.up.right.circle")
    }

    test("navigation: distances and durations read like a sat-nav") {
        expectEqual(NavigationTracker.distanceText(43), "45 M")
        expectEqual(NavigationTracker.distanceText(847), "850 M")
        expectEqual(NavigationTracker.distanceText(2440), "2.4 KM")
        expectEqual(NavigationTracker.durationText(20), "1 MIN")
        expectEqual(NavigationTracker.durationText(3900), "1 H 05")
    }

    test("map scale bar: a round distance between 80 and 220 points at any zoom") {
        for span in [120, 300, 1000, 4000, 8000] {
            let ppm = 470 / Double(span)
            let bar = MinimapPanel.scaleBar(pointsPerMetre: ppm)
            let length = Double(bar.metres) * ppm
            expect(length >= 80 && length <= 220, "span \(span): \(length) pt")
        }
    }

    test("weather: Open-Meteo's forecast decodes to now, the next hours and the week") {
        let json = """
        {"timezone":"Europe/Lisbon",
         "current":{"time":"2026-11-15T14:15","temperature_2m":12.4,"weather_code":61,
                    "apparent_temperature":10.2,"relative_humidity_2m":82,"wind_speed_10m":18.3,
                    "is_day":1},
         "hourly":{"time":["2026-11-15T13:00","2026-11-15T14:00","2026-11-15T15:00"],
                   "temperature_2m":[12,12.6,13.4],"weather_code":[61,61,3],
                   "precipitation_probability":[80,70,30],"is_day":[1,1,0]},
         "daily":{"time":["2026-11-15","2026-11-16"],"weather_code":[61,0],
                  "temperature_2m_max":[14.2,16.8],"temperature_2m_min":[7.1,8.4],
                  "precipitation_probability_max":[70,0],
                  "sunrise":["2026-11-15T07:24","2026-11-16T07:25"],
                  "sunset":["2026-11-15T17:21","2026-11-16T17:20"]}}
        """
        guard let weather = try? OpenMeteoWeatherProvider.decode(
            Data(json.utf8), placeName: "Lisbon", locale: Locale(identifier: "en_GB")) else {
            return expect(false, "did not decode")
        }
        expectEqual(weather.temperature, 12)
        expectEqual(weather.feelsLike, 10)
        expectEqual(weather.humidity, 82)
        expectEqual(weather.sunrise, "7:24")
        // The hour we are in comes first, as "NOW"; the hour already gone is not shown.
        expectEqual(weather.hourly.map(\.label), ["NOW", "15"])
        expectEqual(weather.hourly.last?.symbol, "cloud")
        expectEqual(weather.daily.map(\.label), ["TODAY", "MON"])
        expectEqual(weather.daily.first?.high, 14)
        expectEqual(weather.daily.last?.symbol, "sun.max")
    }

    test("clock: hands follow the time, and another city's offset is signed") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15,
                                                      hour: 21, minute: 30, second: 15))!
        let clock = HudSnapshot.Clock.now(date)
        expectEqual(clock.seconds, "15")
        expectEqual(clock.secondHand, 15)
        expect(abs(clock.hourHand - 9.5042) < 0.001, "hour hand \(clock.hourHand)")

        let utc = TimeZone(identifier: "UTC")!
        let tokyo = HudSnapshot.Clock.worldClock("TOKYO", TimeZone(identifier: "Asia/Tokyo")!,
                                                 at: date, uses24Hour: true, here: utc)
        expectEqual(tokyo.offset, "+9H")
        let same = HudSnapshot.Clock.worldClock("UTC", utc, at: date, uses24Hour: true, here: utc)
        expectEqual(same.offset, "SAME TIME")
    }
}
