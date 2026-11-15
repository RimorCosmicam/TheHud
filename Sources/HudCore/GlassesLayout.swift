import Foundation
import CoreGraphics

/// The four things the glasses can show.
public enum HudPanelKind: String, CaseIterable, Identifiable, Sendable {
    case browser, map, weather, clock

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .browser: return "globe"
        case .map: return "map"
        case .weather: return "cloud.sun"
        case .clock: return "clock"
        }
    }
}

/// The browser chrome's measurements, shared by the view that draws it and the hit test that
/// decides what a click landed on. One set of numbers, so the two cannot disagree.
///
/// The chrome is one floating glass bar, Safari's compact layout: the page runs the full height
/// of the panel and scrolls up underneath it.
public enum BrowserMetrics {
    /// The bar's margin from the panel's edges.
    public static let barInset: CGFloat = 16
    public static let barHeight: CGFloat = 66
    /// Back, forward and reload: hidden until the cursor is on the bar.
    public static let buttonWidth: CGFloat = 78
    public static let panelRadius: CGFloat = 28

    /// Where the page starts when scrolled to the top, so nothing begins hidden under the bar.
    public static var contentTopInset: CGFloat { barInset + barHeight + 10 }
}

/// What a click on the canvas landed on.
public enum GlassesHitTarget: Equatable, Sendable {
    case back
    case forward
    case reload
    case address
    /// A point inside the page, in the web view's own coordinates.
    case page(CGPoint)
    case none
}

/// Where things are on the 1920x1080 canvas.
///
/// The glasses scene takes no touches — every click is the phone's cursor landing somewhere on a
/// canvas the phone cannot see. So the layout is arithmetic rather than something read back from
/// the view tree: the controller has to answer "what is under the cursor" without a view to ask,
/// and arithmetic can be tested on a Mac.
public struct GlassesLayout: Sendable {
    public static let columnWidth: CGFloat = 470
    public static let gap: CGFloat = 24

    public var visible: Set<HudPanelKind>

    public init(visible: Set<HudPanelKind> = Set(HudPanelKind.allCases)) {
        self.visible = visible
    }

    /// The clock, weather and map share one column beside the browser.
    public var hasColumn: Bool { !visible.isDisjoint(with: [.clock, .weather, .map]) }

    public var browserFrame: CGRect? {
        guard visible.contains(.browser) else { return nil }
        let inset = HudTheme.safeInset
        let canvas = HudTheme.glassesSize
        let x = inset + (hasColumn ? Self.columnWidth + Self.gap : 0)
        return CGRect(x: x, y: inset,
                      width: canvas.width - inset - x,
                      height: canvas.height - inset * 2)
    }

    /// The page: the whole panel, because the bar floats over it.
    public var contentFrame: CGRect? { browserFrame }

    /// The glass bar.
    public var barFrame: CGRect? {
        guard let frame = browserFrame else { return nil }
        let inset = BrowserMetrics.barInset
        return CGRect(x: frame.minX + inset, y: frame.minY + inset,
                      width: frame.width - inset * 2, height: BrowserMetrics.barHeight)
    }

    /// Whether the cursor is over the bar, which is what brings its buttons up.
    public func isOverBar(_ point: CGPoint?) -> Bool {
        guard let point, let bar = barFrame else { return false }
        return bar.contains(point)
    }

    public func hitTest(_ point: CGPoint) -> GlassesHitTarget {
        guard let frame = browserFrame, frame.contains(point) else { return .none }

        if let bar = barFrame, bar.contains(point) {
            let x = point.x - bar.minX
            let button = BrowserMetrics.buttonWidth
            if x < button { return .back }
            if x < button * 2 { return .forward }
            if x >= bar.width - button { return .reload }
            return .address
        }

        return .page(CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
    }
}

/// Turns what was typed into the address bar into somewhere to go.
public enum AddressInput {
    public static func url(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://"), let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        // No spaces and a dot reads as a host; anything else is a search.
        if !trimmed.contains(" "), trimmed.contains("."),
           let url = URL(string: "https://" + trimmed), url.host != nil {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }
}

/// What a keyboard would have sent to turn one string into another: back up to where they
/// diverge, then type the rest. Autocorrect replacing a word arrives the same way as typing.
public enum TextEdit {
    public static func between(_ old: String, _ new: String) -> (deletes: Int, insert: String) {
        let common = zip(old, new).prefix { $0 == $1 }.count
        return (old.count - common, String(new.dropFirst(common)))
    }
}
