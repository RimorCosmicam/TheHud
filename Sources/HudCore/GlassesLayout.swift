import Foundation
import CoreGraphics

/// Everything the glasses can show: two big things for the middle, and the widgets that sit in
/// the slots either side of it.
public enum HudPanelKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case browser, mac
    case clock, weather, map, activity, sky, music, note, captions, youtube
    case calendar, photos, prompter, camera

    public var id: String { rawValue }

    /// The browser and the Mac: drawn by panels of their own, with live content, and what the
    /// cursor mostly works on. In a slot they are a live preview of the same content.
    public var isBig: Bool { self == .browser || self == .mac }

    /// Every app, in the order the phone's picker lists them. Any of them can be a widget, the
    /// one app in the centre, or fullscreen.
    public static let apps: [HudPanelKind] = [.browser, .mac, .youtube, .map, .music, .calendar,
                                              .photos, .camera, .prompter, .note, .sky, .weather,
                                              .clock, .activity, .captions]

    public var symbol: String {
        switch self {
        case .browser: return "globe"
        case .mac: return "desktopcomputer"
        case .clock: return "clock"
        case .weather: return "cloud.sun"
        case .map: return "map"
        case .activity: return "figure.walk"
        case .sky: return "moon.stars"
        case .music: return "music.note"
        case .note: return "note.text"
        case .captions: return "captions.bubble"
        case .youtube: return "play.rectangle"
        case .calendar: return "calendar"
        case .photos: return "photo.on.rectangle"
        case .prompter: return "text.alignleft"
        case .camera: return "camera"
        }
    }

    public var title: String {
        switch self {
        case .music: return "MUSIC"
        default: return rawValue.uppercased()
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
    /// A point on the Mac's picture, as fractions of it (0...1 each way).
    case mac(CGPoint)
    /// A widget, or a widget's fullscreen app: the point inside it, and its size.
    case widget(HudPanelKind, CGPoint, CGSize)
    /// The app in the centre (not the browser or the Mac, which have their own): the point
    /// inside it, and its size.
    case centre(HudPanelKind, CGPoint, CGSize)
    case none
}

/// Where things are on the 1920x1080 canvas.
///
/// Three slots down each side for widgets; the middle for the browser and the Mac. Either of
/// those can reach over one side as well, hiding the widgets there, or be held up alone.
///
/// The glasses scene takes no touches — every click is the phone's cursor landing somewhere on a
/// canvas the phone cannot see. So the layout is arithmetic rather than something read back from
/// the view tree: the controller has to answer "what is under the cursor" without a view to ask,
/// and arithmetic can be tested on a Mac. The phone's miniature is this same arithmetic, scaled.
public struct GlassesLayout: Sendable {
    public static let slotWidth: CGFloat = 400
    public static let gap: CGFloat = 24
    public static var slotHeight: CGFloat {
        (HudTheme.glassesSize.height - HudTheme.safeInset * 2 - gap * 2) / 3
    }

    public var arrangement: HudArrangement
    /// One panel held up alone.
    public var solo: HudPanelKind?
    /// Everything off: the glasses show the world.
    public var clearView: Bool
    public var tabCount: Int
    public var activeTab: Int
    /// A video (or any page element) has asked for fullscreen: the browser is the whole canvas,
    /// with no bar and no panels.
    public var fullscreen: Bool
    /// The Mac picture's width over its height, to fit it in its panel.
    public var desktopAspect: CGFloat

    public init(arrangement: HudArrangement = .standard, solo: HudPanelKind? = nil,
                clearView: Bool = false,
                tabCount: Int = 1, activeTab: Int = 0, fullscreen: Bool = false,
                desktopAspect: CGFloat = 16 / 10) {
        self.arrangement = arrangement
        self.solo = solo
        self.clearView = clearView
        self.tabCount = max(tabCount, 1)
        self.activeTab = activeTab
        self.desktopAspect = desktopAspect > 0 ? desktopAspect : 16 / 10
        let browserShown = solo.map { $0 == .browser } ?? arrangement.isShown(.browser)
        self.fullscreen = fullscreen && browserShown && !clearView
    }

    /// The set as a plain list of what is on: widgets fill the left slots, then the right, and
    /// the big ones share the middle. For stills and tests.
    public init(visible: Set<HudPanelKind>, tabCount: Int = 1, activeTab: Int = 0,
                fullscreen: Bool = false, desktopAspect: CGFloat = 16 / 10) {
        self.init(arrangement: HudArrangement(visible: visible), tabCount: tabCount,
                  activeTab: activeTab, fullscreen: fullscreen, desktopAspect: desktopAspect)
    }

    /// The canvas inside the safe inset.
    public static var safeFrame: CGRect {
        let inset = HudTheme.safeInset
        return CGRect(x: inset, y: inset, width: HudTheme.glassesSize.width - inset * 2,
                      height: HudTheme.glassesSize.height - inset * 2)
    }

    /// The row layout's band of widgets: shorter than a column slot, so the app under or over
    /// it keeps most of the view.
    public static let rowHeight: CGFloat = 270

    public static func rowFrame(_ index: Int, along edge: HudEdge) -> CGRect {
        let safe = safeFrame
        let count = CGFloat(HudArrangement.rowSlots)
        let width = (safe.width - gap * (count - 1)) / count
        return CGRect(x: safe.minX + CGFloat(index) * (width + gap),
                      y: edge == .top ? safe.minY : safe.maxY - rowHeight,
                      width: width, height: rowHeight)
    }

    /// Everything the row leaves: the one big panel's place.
    public static func rowMain(along edge: HudEdge) -> CGRect {
        let safe = safeFrame
        return CGRect(x: safe.minX, y: edge == .top ? safe.minY + rowHeight + gap : safe.minY,
                      width: safe.width, height: safe.height - rowHeight - gap)
    }

    public static func slotFrame(_ side: HudSide, _ index: Int) -> CGRect {
        let safe = safeFrame
        let x = side == .left ? safe.minX : safe.maxX - slotWidth
        return CGRect(x: x, y: safe.minY + CGFloat(index) * (slotHeight + gap),
                      width: slotWidth, height: slotHeight)
    }

    /// The middle, plus any side a big panel has taken over.
    public static func bigSpan(taking sides: Set<HudSide>) -> CGRect {
        let safe = safeFrame
        let minX = sides.contains(.left) ? safe.minX : safe.minX + slotWidth + gap
        let maxX = sides.contains(.right) ? safe.maxX : safe.maxX - slotWidth - gap
        return CGRect(x: minX, y: safe.minY, width: maxX - minX, height: safe.height)
    }

    private var drawsArrangement: Bool { !clearView && solo == nil && !fullscreen }

    /// The widgets on the canvas and where: not hidden, not under a big panel's side.
    public var widgetFrames: [(kind: HudPanelKind, frame: CGRect)] {
        guard drawsArrangement else { return [] }
        if let edge = arrangement.strip {
            return arrangement.shownRow.map { ($0.kind, Self.rowFrame($0.index, along: edge)) }
        }
        return arrangement.shownWidgets.map { ($0.kind, Self.slotFrame($0.side, $0.index)) }
    }

    /// The Apps Center: whatever app is in the centre, and where. Nil when it is switched off,
    /// or something is fullscreen.
    public var centre: (kind: HudPanelKind, frame: CGRect)? {
        guard drawsArrangement, let big = arrangement.orderedBigs.first else { return nil }
        if let edge = arrangement.strip { return (big.kind, Self.rowMain(along: edge)) }
        return (big.kind, Self.bigSpan(taking: arrangement.takenSides))
    }

    /// The centre when it holds an app other than the browser or the Mac.
    public var centreApp: (kind: HudPanelKind, frame: CGRect)? {
        guard let centre, !centre.kind.isBig else { return nil }
        return centre
    }

    /// The browser's and the Mac's panels on the canvas: in the centre, held up alone, or the
    /// browser's page fullscreen. In a slot they are widgets, not these.
    public var bigFrames: [(kind: HudPanelKind, frame: CGRect)] {
        if clearView { return [] }
        if fullscreen { return [(.browser, CGRect(origin: .zero, size: HudTheme.glassesSize))] }
        if let solo {
            return solo.isBig ? [(solo, Self.safeFrame)] : []
        }
        guard let centre, centre.kind.isBig else { return [] }
        return [centre]
    }

    /// Where a widget's fullscreen app is drawn and clicked.
    public var soloWidgetFrame: CGRect? {
        guard !clearView, !fullscreen, let solo, !solo.isBig else { return nil }
        return Self.safeFrame
    }

    public func frame(of kind: HudPanelKind) -> CGRect? {
        if kind.isBig { return bigFrames.first { $0.kind == kind }?.frame }
        if solo == kind { return soloWidgetFrame }
        if let centre, centre.kind == kind { return centre.frame }
        return widgetFrames.first { $0.kind == kind }?.frame
    }

    public var browserFrame: CGRect? { frame(of: .browser) }

    /// The Mac panel. Not while a video has the browser fullscreen.
    public var desktopFrame: CGRect? { frame(of: .mac) }

    /// The Mac's picture inside its panel, fitted without cropping.
    public var desktopPicture: CGRect? {
        guard let frame = desktopFrame else { return nil }
        let width = min(frame.width, frame.height * desktopAspect)
        let height = width / desktopAspect
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2,
                      width: width, height: height)
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
        if clearView { return .none }
        if let frame = soloWidgetFrame, let solo {
            return .widget(solo, CGPoint(x: point.x - frame.minX, y: point.y - frame.minY),
                           frame.size)
        }
        if let picture = desktopPicture, picture.contains(point) {
            return .mac(CGPoint(x: (point.x - picture.minX) / picture.width,
                                y: (point.y - picture.minY) / picture.height))
        }
        for (kind, frame) in widgetFrames where frame.contains(point) {
            return .widget(kind, CGPoint(x: point.x - frame.minX, y: point.y - frame.minY),
                           frame.size)
        }
        if let (kind, frame) = centreApp, frame.contains(point) {
            return .centre(kind, CGPoint(x: point.x - frame.minX, y: point.y - frame.minY),
                           frame.size)
        }
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
