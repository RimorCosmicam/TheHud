import SwiftUI
import CoreText

/// MiniMate's "Mont" panel material, carried over unchanged: black at ninety-two percent, Mont in
/// white, no border and no corner rounding. State is carried by brightness alone.
///
/// It is the right material for glasses as well as for a cover display — a hairline and a rounded
/// corner both cost contrast, and contrast is the one thing a transparent display is short of.
public enum HudTheme {
    public static let surfaceAlpha: Double = 0.92
    public static let surface = Color.black.opacity(surfaceAlpha)
    public static let ink = Color.white
    public static let inkDim = Color.white.opacity(0.55)
    public static let inkFaint = Color.white.opacity(0.28)

    /// MiniMate's Mustard accent (`uC2` of the default colorway), for the few marks that carry state.
    public static let accent = Color(red: 0xD8 / 255, green: 0xA6 / 255, blue: 0x28 / 255)

    /// The glasses' own canvas. The Air reports 1920x1080 over DisplayPort.
    public static let glassesSize = CGSize(width: 1920, height: 1080)

    /// Xreal's optics are uncomfortable to read at the extreme edge of the field, so the HUD keeps
    /// off the rim rather than filling the panel.
    public static let safeInset: CGFloat = 64

    private static let registerFonts: Void = {
        for name in ["mont_thin", "mont_light", "mont_regular", "mont_semibold", "mont_black"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf",
                                              subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Registers Mont once. Safe to call repeatedly; the work happens on first touch.
    public static func bootstrap() { _ = registerFonts }

    public static func mont(_ size: CGFloat, _ weight: MontWeight = .black) -> Font {
        bootstrap()
        return .custom(weight.postScriptName, fixedSize: size)
    }

    public enum MontWeight {
        case thin, light, regular, semibold, black

        /// The TTFs install under their family name plus style; these are the PostScript names
        /// CoreText exposes them under once registered.
        var postScriptName: String {
            switch self {
            case .thin: return "Mont-Thin"
            case .light: return "Mont-Light"
            case .regular: return "Mont-Regular"
            case .semibold: return "Mont-SemiBold"
            case .black: return "Mont-Black"
            }
        }
    }
}

/// The Mont panel, as a modifier so every surface on the HUD is the same decision made once.
public struct HudPanel: ViewModifier {
    public var padding: CGFloat

    public init(padding: CGFloat = 28) { self.padding = padding }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(HudTheme.surface)
    }
}

public extension View {
    func hudPanel(padding: CGFloat = 28) -> some View { modifier(HudPanel(padding: padding)) }

    /// The small all-caps label that titles a panel.
    func hudLabel() -> some View {
        self.font(HudTheme.mont(16, .black))
            .tracking(3)
            .foregroundStyle(HudTheme.inkDim)
    }
}
