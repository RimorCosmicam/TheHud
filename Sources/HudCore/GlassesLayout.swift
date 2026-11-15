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
public enum BrowserMetrics {
    public static let tabHeight: CGFloat = 54
    public static let addressHeight: CGFloat = 76
    public static let dividerHeight: CGFloat = 1
    public static let sidePadding: CGFloat = 12
    public static let navButtonWidth: CGFloat = 52
    public static let reloadWidth: CGFloat = 64
    public static let fieldGap: CGFloat = 10
    public static let fieldHeight: CGFloat = 50

    public static var chromeHeight: CGFloat { tabHeight + addressHeight + dividerHeight }
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

    /// The page itself: the browser's frame less its chrome.
    public var contentFrame: CGRect? {
        guard let frame = browserFrame else { return nil }
        return CGRect(x: frame.minX, y: frame.minY + BrowserMetrics.chromeHeight,
                      width: frame.width, height: frame.height - BrowserMetrics.chromeHeight)
    }

    public func hitTest(_ point: CGPoint) -> GlassesHitTarget {
        guard let frame = browserFrame, frame.contains(point) else { return .none }

        let x = point.x - frame.minX
        let y = point.y - frame.minY

        if y < BrowserMetrics.tabHeight { return .none }

        if y < BrowserMetrics.tabHeight + BrowserMetrics.addressHeight {
            let left = BrowserMetrics.sidePadding
            let nav = BrowserMetrics.navButtonWidth
            let right = frame.width - BrowserMetrics.sidePadding

            if x >= left && x < left + nav { return .back }
            if x >= left + nav && x < left + nav * 2 { return .forward }
            if x >= right - BrowserMetrics.reloadWidth && x < right { return .reload }
            if x >= left + nav * 2 && x < right - BrowserMetrics.reloadWidth { return .address }
            return .none
        }

        let pageY = y - BrowserMetrics.chromeHeight
        return pageY >= 0 ? .page(CGPoint(x: x, y: pageY)) : .none
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

        var components = URLComponents(string: "https://duckduckgo.com/")!
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
