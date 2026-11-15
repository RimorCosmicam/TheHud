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
    public static var panelRadius: CGFloat { HudTheme.cornerRadius }

    /// Where the page starts when scrolled to the top, so nothing begins hidden under the bar.
    public static var contentTopInset: CGFloat { barInset + barHeight + 10 }

    /// More tabs than this and each one is too narrow to read or hit.
    public static let maxTabs = 8
    /// The close mark at the left end of a hovered tab.
    public static let closeWidth: CGFloat = 52

    /// Where each tab sits along the bar, in the bar's own coordinates.
    ///
    /// Back and forward take the left end, new tab and reload the right; the tabs share what is
    /// between. The active tab gets two shares, as in Safari's compact layout, so its title stays
    /// readable however many others there are. One tab takes the whole middle.
    public static func tabSegments(barWidth: CGFloat, count: Int, active: Int)
        -> [(x: CGFloat, width: CGFloat)] {
        let left = buttonWidth * 2
        let middle = max(barWidth - buttonWidth * 4, 0)
        guard count > 1 else { return [(left, middle)] }
        let unit = middle / CGFloat(count + 1)
        var x = left
        return (0..<count).map { index in
            let width = unit * (index == active ? 2 : 1)
            defer { x += width }
            return (x, width)
        }
    }
}

/// What a click on the canvas landed on.
public enum GlassesHitTarget: Equatable, Sendable {
    case back
    case forward
    case reload
    case address
    case newTab
    case selectTab(Int)
    case closeTab(Int)
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
    public var tabCount: Int
    public var activeTab: Int
    /// A video (or any page element) has asked for fullscreen: the browser is the whole canvas,
    /// with no bar and no panels.
    public var fullscreen: Bool

    public init(visible: Set<HudPanelKind> = Set(HudPanelKind.allCases),
                tabCount: Int = 1, activeTab: Int = 0, fullscreen: Bool = false) {
        self.visible = visible
        self.fullscreen = fullscreen && visible.contains(.browser)
        self.tabCount = max(tabCount, 1)
        self.activeTab = activeTab
    }

    /// The clock, weather and map share one column beside the browser.
    public var hasColumn: Bool { !visible.isDisjoint(with: [.clock, .weather, .map]) }

    public var browserFrame: CGRect? {
        guard visible.contains(.browser) else { return nil }
        if fullscreen { return CGRect(origin: .zero, size: HudTheme.glassesSize) }
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
        guard !fullscreen, let frame = browserFrame else { return nil }
        let inset = BrowserMetrics.barInset
        return CGRect(x: frame.minX + inset, y: frame.minY + inset,
                      width: frame.width - inset * 2, height: BrowserMetrics.barHeight)
    }

    /// Whether the cursor is over the bar, which is what brings its buttons up.
    public func isOverBar(_ point: CGPoint?) -> Bool {
        guard let point, let bar = barFrame else { return false }
        return bar.contains(point)
    }

    /// The tab under a point, if it is on the strip.
    public func tab(at point: CGPoint?) -> Int? {
        guard let point, let bar = barFrame, bar.contains(point) else { return nil }
        let x = point.x - bar.minX
        let segments = BrowserMetrics.tabSegments(barWidth: bar.width, count: tabCount,
                                                  active: activeTab)
        return segments.firstIndex { x >= $0.x && x < $0.x + $0.width }
    }

    public func hitTest(_ point: CGPoint) -> GlassesHitTarget {
        guard let frame = browserFrame, frame.contains(point) else { return .none }

        if let bar = barFrame, bar.contains(point) {
            let x = point.x - bar.minX
            let button = BrowserMetrics.buttonWidth
            if x < button { return .back }
            if x < button * 2 { return .forward }
            if x >= bar.width - button { return .reload }
            if x >= bar.width - button * 2 { return .newTab }

            let segments = BrowserMetrics.tabSegments(barWidth: bar.width, count: tabCount,
                                                      active: activeTab)
            guard let index = segments.firstIndex(where: { x >= $0.x && x < $0.x + $0.width })
            else { return .none }
            // With one tab there is nothing to close it into.
            if tabCount > 1, x < segments[index].x + BrowserMetrics.closeWidth {
                return .closeTab(index)
            }
            return index == activeTab ? .address : .selectTab(index)
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

/// What a click on the Maps app landed on.
public enum MapsHitTarget: Equatable, Sendable {
    case search
    case result(Int)
    case endRoute
    case transport
    case zoomIn
    case zoomOut
    case none
}

/// The Maps app's floating controls, for drawing and for hit testing, as `GlassesLayout` is for
/// the browser.
public struct MapsLayout: Sendable {
    public var resultCount: Int
    public var navigating: Bool

    public init(resultCount: Int = 0, navigating: Bool = false) {
        self.resultCount = resultCount
        self.navigating = navigating
    }

    public static let margin: CGFloat = 28
    public static let cardWidth: CGFloat = 640
    public static let searchHeight: CGFloat = 72
    public static let rowHeight: CGFloat = 88
    public static let buttonSize: CGFloat = 76
    public static let tripHeight: CGFloat = 104
    public static let tripButtonWidth: CGFloat = 132

    /// The map itself: the canvas inside the safe inset.
    public var panel: CGRect {
        let inset = HudTheme.safeInset
        return CGRect(x: inset, y: inset, width: HudTheme.glassesSize.width - inset * 2,
                      height: HudTheme.glassesSize.height - inset * 2)
    }

    public var searchFrame: CGRect {
        CGRect(x: panel.minX + Self.margin, y: panel.minY + Self.margin,
               width: Self.cardWidth, height: Self.searchHeight)
    }

    public func resultFrame(_ index: Int) -> CGRect {
        CGRect(x: searchFrame.minX, y: searchFrame.maxY + 12 + CGFloat(index) * Self.rowHeight,
               width: Self.cardWidth, height: Self.rowHeight)
    }

    /// Next turn, top left, where the search field is when not navigating.
    public var turnFrame: CGRect {
        CGRect(x: searchFrame.minX, y: searchFrame.minY, width: Self.cardWidth, height: 200)
    }

    /// Time, distance and arrival, bottom left, with the transport and end buttons at its end.
    public var tripFrame: CGRect {
        CGRect(x: panel.minX + Self.margin, y: panel.maxY - Self.margin - Self.tripHeight,
               width: Self.cardWidth + 260, height: Self.tripHeight)
    }

    public var endFrame: CGRect {
        CGRect(x: tripFrame.maxX - 12 - Self.tripButtonWidth, y: tripFrame.minY + 14,
               width: Self.tripButtonWidth, height: tripFrame.height - 28)
    }

    public var transportFrame: CGRect {
        endFrame.offsetBy(dx: -(Self.tripButtonWidth + 10), dy: 0)
    }

    public var zoomInFrame: CGRect {
        CGRect(x: panel.maxX - Self.margin - Self.buttonSize, y: panel.midY - Self.buttonSize - 6,
               width: Self.buttonSize, height: Self.buttonSize)
    }

    public var zoomOutFrame: CGRect { zoomInFrame.offsetBy(dx: 0, dy: Self.buttonSize + 12) }

    public func hitTest(_ point: CGPoint) -> MapsHitTarget {
        if zoomInFrame.contains(point) { return .zoomIn }
        if zoomOutFrame.contains(point) { return .zoomOut }
        if navigating {
            if endFrame.contains(point) { return .endRoute }
            if transportFrame.contains(point) { return .transport }
            return .none
        }
        if searchFrame.contains(point) { return .search }
        for index in 0..<resultCount where resultFrame(index).contains(point) {
            return .result(index)
        }
        return .none
    }
}
