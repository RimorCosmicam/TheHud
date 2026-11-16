import Foundation
import SwiftUI
import Observation

/// The app's one colour: the accent on the glasses and the phone, the touchpad's halftone, and
/// the app icon.
///
/// Every theme is the mustard turned round the colour wheel, in OKLCH rather than plain HSL:
/// OKLCH keeps the perceived lightness, so each colour is as bright as the mustard and reads the
/// same way on the dark app — bright marks on black, black text on an accent chip. Where a hue
/// cannot be that bright at full colour (blues), the colour gives up saturation, never lightness.
public enum ThemeColor: String, CaseIterable, Identifiable, Sendable, Codable {
    case mustard, lime, mint, sky, iris, orchid, rose, coral

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    /// Degrees round the OKLCH hue circle from the mustard.
    public var shift: Double {
        switch self {
        case .mustard: return 0
        case .lime: return 40
        case .mint: return 90
        case .sky: return 150
        case .iris: return 200
        case .orchid: return 245
        case .rose: return 280
        case .coral: return 315
        }
    }

    /// Any colour of the mustard theme, in this one. ARGB, alpha kept.
    public func color(_ argb: UInt32) -> UInt32 { OKLCH.rotate(argb, by: shift) }

    /// The accent: the mustard's `D8A628`, turned.
    public var accentARGB: UInt32 { color(0xFFD8A628) }
    public var accent: Color { Color(argb: accentARGB) }

    /// The touchpad's halftone in this colour.
    public var colorway: Colorway {
        let m = Colorway.mustardFlat.stops
        return Colorway(label: title, color(m[0]), color(m[1]), color(m[2]), color(m[3]))
    }

    /// The alternate icon's name in the asset catalog; nil is the primary, mustard icon.
    public var iconName: String? { self == .mustard ? nil : "AppIcon-\(title)" }
}

/// The chosen theme, observed: any view whose body reads `HudTheme.accent` redraws when it changes,
/// with no environment to thread through.
@Observable
public final class ThemeStore: @unchecked Sendable {
    public static let shared = ThemeStore()

    public var color: ThemeColor = .mustard {
        didSet { if color != oldValue { accent = color.accent } }
    }
    public private(set) var accent: Color = ThemeColor.mustard.accent

    private init() {}
}

/// OKLab (Björn Ottosson's), for turning a colour's hue while keeping how light it looks.
public enum OKLCH {
    public static func rotate(_ argb: UInt32, by degrees: Double) -> UInt32 {
        guard degrees != 0 else { return argb }
        let (L, a, b) = lab(argb)
        let chroma = (a * a + b * b).squareRoot()
        guard chroma > 1e-4 else { return argb }   // greys have no hue to turn
        let hue = atan2(b, a) + degrees * .pi / 180
        // As much of the colour as fits in sRGB at this lightness.
        var lo = 0.0, hi = 1.0
        if !inGamut(rgb(L, chroma * cos(hue), chroma * sin(hue))) {
            for _ in 0..<24 {
                let k = (lo + hi) / 2
                if inGamut(rgb(L, chroma * k * cos(hue), chroma * k * sin(hue))) { lo = k } else { hi = k }
            }
        } else {
            lo = 1
        }
        let c = rgb(L, chroma * lo * cos(hue), chroma * lo * sin(hue))
        return (argb & 0xFF00_0000) | (byte(c.0) << 16) | (byte(c.1) << 8) | byte(c.2)
    }

    static func lab(_ argb: UInt32) -> (Double, Double, Double) {
        let r = linear(Double((argb >> 16) & 0xFF) / 255)
        let g = linear(Double((argb >> 8) & 0xFF) / 255)
        let b = linear(Double(argb & 0xFF) / 255)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func rgb(_ L: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
        let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private static func inGamut(_ c: (Double, Double, Double)) -> Bool {
        let e = 1e-4
        return c.0 >= -e && c.0 <= 1 + e && c.1 >= -e && c.1 <= 1 + e && c.2 >= -e && c.2 <= 1 + e
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func byte(_ linear: Double) -> UInt32 {
        let c = min(max(linear, 0), 1)
        let s = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt32((s * 255).rounded())
    }
}

public extension Color {
    init(argb: UInt32) {
        self.init(red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}
