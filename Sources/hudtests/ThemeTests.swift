import Foundation
import HudCore

func runThemeTests() {
    print("\nTheme colours")

    func luminance(_ argb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((argb >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    test("mustard is the original mustard, untouched") {
        expectEqual(ThemeColor.mustard.accentARGB, 0xFFD8A628)
        expectEqual(ThemeColor.mustard.colorway.stops, Colorway.mustardFlat.stops)
        expect(ThemeColor.mustard.iconName == nil, "the primary icon")
    }

    test("eight colours, each its own") {
        expectEqual(ThemeColor.allCases.count, 8)
        expectEqual(Set(ThemeColor.allCases.map(\.accentARGB)).count, 8)
        expectEqual(Set(ThemeColor.allCases.compactMap(\.iconName)).count, 7)
    }

    test("every accent reads on the dark app: bright on black, and black text on it") {
        for theme in ThemeColor.allCases {
            let contrast = (luminance(theme.accentARGB) + 0.05) / 0.05
            expectGreater(contrast, 7.0, "\(theme.title) against black")
        }
    }

    test("the halftone keeps a dark ground and a bright top in every colour") {
        for theme in ThemeColor.allCases {
            let stops = theme.colorway.stops
            expectLess(luminance(stops[0]), 0.02, "\(theme.title) ground")
            expectGreater(luminance(stops[3]), 0.7, "\(theme.title) highlight")
        }
    }

    test("the accents, pinned: Android's CoreTest expects the same eight") {
        expectEqual(ThemeColor.allCases.map(\.accentARGB),
                    [0xFFD8A628, 0xFF9ABE50, 0xFF00CBA9, 0xFF36BCFC, 0xFFA6A2FF, 0xFFE18BDA, 0xFFF985A2, 0xFFFA8C66])
    }

    test("greys have no hue to turn") {
        expectEqual(ThemeColor.sky.color(0xFF000000), 0xFF000000)
        expectEqual(ThemeColor.sky.color(0xFFFFFFFF), 0xFFFFFFFF)
        expectEqual(ThemeColor.rose.color(0xFF808080), 0xFF808080)
    }

    test("the Android phone is told the theme by name") {
        let m = RemoteWire.theme(.orchid)
        expectEqual(m["t"] as? String, "theme")
        expectEqual(m["color"] as? String, "orchid")
    }
}
