import Foundation

public enum HudSide: String, Codable, Sendable, CaseIterable {
    case left, right
}

/// The edge a row of widgets runs along, in the row layout.
public enum HudEdge: String, Codable, Sendable, CaseIterable {
    case top, bottom
}

/// Where something can be dropped in the phone's editor.
public enum HudSpot: Equatable, Sendable {
    case slot(HudSide, Int)
    /// One of the row layout's widget places, left to right.
    case row(Int)
    /// The middle of the glasses: where the browser and the Mac go.
    case middle
    /// Off the glasses: back with the icons.
    case off
}

/// What is on the glasses and where, in one of two layouts.
///
/// Every app has three sizes: a widget in a slot, the one app in the centre (the Apps Center),
/// or fullscreen when held. Columns: three widget slots down each side and the centre between,
/// which can reach over one side. Row: four widgets along the top or the bottom, and the centre
/// in the rest; quieter, for walking. An app is in one place at a time.
///
/// Each layout keeps its own slots, so switching back and forth loses nothing; the centre is
/// shared. Edited on the phone and saved; the glasses layout is arithmetic over this.
public struct HudArrangement: Codable, Equatable, Sendable {
    public static let slotsPerSide = 3
    public static let rowSlots = 4

    /// The row layout's widgets, left to right.
    public var row: [HudPanelKind?]
    /// Nil for columns; otherwise the edge the row runs along.
    public var strip: HudEdge?
    public var isRow: Bool { strip != nil }

    public var left: [HudPanelKind?]
    public var right: [HudPanelKind?]
    /// The centre, as a list of at most one: the app in it, and the side it reaches over.
    public var bigs: [Big]
    /// Placed but switched off for now with a tap; they keep their place.
    public var hidden: Set<HudPanelKind>

    public struct Big: Codable, Equatable, Sendable {
        public var kind: HudPanelKind
        /// The side it reaches over, hiding the widgets there. Nil: the middle only.
        public var side: HudSide?
        public init(kind: HudPanelKind, side: HudSide? = nil) {
            self.kind = kind
            self.side = side
        }
    }

    /// The Apps Center: the one app in the middle, whether switched off for now or not.
    public var centre: Big? { bigs.first }

    public init(left: [HudPanelKind?] = [nil, nil, nil], right: [HudPanelKind?] = [nil, nil, nil],
                centre: Big? = nil, hidden: Set<HudPanelKind> = [],
                row: [HudPanelKind?] = [], strip: HudEdge? = nil) {
        self.left = Self.padded(left)
        self.right = Self.padded(right)
        self.bigs = centre.map { [$0] } ?? []
        self.hidden = hidden
        self.row = Self.padded(row, to: Self.rowSlots)
        self.strip = strip
    }

    /// Arrangements saved before the row layout have neither of its fields; ones from before
    /// the Apps Center can have two apps in the middle, of which the first stays.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        left = Self.padded(try container.decode([HudPanelKind?].self, forKey: .left))
        right = Self.padded(try container.decode([HudPanelKind?].self, forKey: .right))
        bigs = Array(try container.decode([Big].self, forKey: .bigs).prefix(1))
        hidden = try container.decode(Set<HudPanelKind>.self, forKey: .hidden)
        row = Self.padded(try container.decodeIfPresent([HudPanelKind?].self, forKey: .row) ?? [],
                          to: Self.rowSlots)
        strip = try container.decodeIfPresent(HudEdge.self, forKey: .strip)
    }

    /// The browser in the centre; the clock, the weather and the map down the left.
    public static let standard = HudArrangement(left: [.clock, .weather, .map],
                                                centre: Big(kind: .browser))

    /// The set as a plain list: the browser (or else the Mac) in the centre, and the rest as
    /// widgets filling the left slots then the right. For stills and tests.
    public init(visible: Set<HudPanelKind>) {
        let centre: HudPanelKind? = visible.contains(.browser) ? .browser : visible.contains(.mac) ? .mac : nil
        let widgets = HudPanelKind.allCases.filter { visible.contains($0) && $0 != centre && !$0.isBig }
            + HudPanelKind.allCases.filter { visible.contains($0) && $0 != centre && $0.isBig }
        let list = Array(widgets.prefix(Self.slotsPerSide * 2))
        self.init(left: Array(list.prefix(3)), right: Array(list.dropFirst(3)),
                  centre: centre.map { Big(kind: $0) })
    }

    private static func padded(_ slots: [HudPanelKind?], to count: Int = slotsPerSide) -> [HudPanelKind?] {
        Array((slots + Array(repeating: nil, count: count)).prefix(count))
    }

    /// Switches layout. The first time into the row, it takes the first four widgets that were
    /// showing; after that each layout remembers its own.
    public mutating func setStrip(_ edge: HudEdge?) {
        if edge != nil, !isRow, row.allSatisfy({ $0 == nil }) {
            let widgets = (left + right).compactMap { $0 }.filter { !hidden.contains($0) }
            row = Self.padded(Array(widgets.prefix(Self.rowSlots)), to: Self.rowSlots)
        }
        strip = edge
    }

    public func slots(_ side: HudSide) -> [HudPanelKind?] { side == .left ? left : right }

    private mutating func setSlot(_ side: HudSide, _ index: Int, _ kind: HudPanelKind?) {
        if side == .left { left[index] = kind } else { right[index] = kind }
    }

    /// Where a kind is now, if it is placed.
    public func spot(of kind: HudPanelKind) -> HudSpot {
        if centre?.kind == kind { return .middle }
        if isRow {
            if let index = row.firstIndex(of: kind) { return .row(index) }
            return .off
        }
        for side in HudSide.allCases {
            if let index = slots(side).firstIndex(of: kind) { return .slot(side, index) }
        }
        return .off
    }

    public func isPlaced(_ kind: HudPanelKind) -> Bool { spot(of: kind) != .off }
    public func isShown(_ kind: HudPanelKind) -> Bool { isPlaced(kind) && !hidden.contains(kind) }

    /// The side the centre reaches over, if any.
    public func side(of kind: HudPanelKind) -> HudSide? {
        if isRow { return nil }
        return centre?.kind == kind ? centre?.side : nil
    }

    /// The centre as it is on the glasses: nothing when switched off, and never over a side in
    /// the row layout.
    public var orderedBigs: [Big] {
        guard let centre, !hidden.contains(centre.kind) else { return [] }
        return [isRow ? Big(kind: centre.kind) : centre]
    }

    /// Sides the shown centre has taken over.
    public var takenSides: Set<HudSide> {
        Set(orderedBigs.compactMap(\.side))
    }

    /// Widgets that are drawn: placed, not switched off, and not under the centre's side.
    public var shownWidgets: [(kind: HudPanelKind, side: HudSide, index: Int)] {
        if isRow { return [] }
        let taken = takenSides
        return HudSide.allCases.flatMap { side -> [(kind: HudPanelKind, side: HudSide, index: Int)] in
            guard !taken.contains(side) else { return [] }
            return slots(side).enumerated().compactMap { index, kind in
                guard let kind, !hidden.contains(kind) else { return nil }
                return (kind, side, index)
            }
        }
    }

    /// The row layout's widgets that are drawn: placed and not switched off.
    public var shownRow: [(kind: HudPanelKind, index: Int)] {
        guard isRow else { return [] }
        return row.enumerated().compactMap { index, kind in
            guard let kind, !hidden.contains(kind) else { return nil }
            return (kind, index)
        }
    }

    /// Everything not placed: the icons under the miniature while editing.
    public var unplaced: [HudPanelKind] {
        HudPanelKind.apps.filter { !isPlaced($0) }
    }

    /// Takes a kind off the glasses.
    public mutating func remove(_ kind: HudPanelKind) {
        if centre?.kind == kind { bigs = [] }
        if isRow {
            // Only from the layout in use: the columns keep theirs for coming back to.
            row = row.map { $0 == kind ? nil : $0 }
        } else {
            for side in HudSide.allCases {
                if let index = slots(side).firstIndex(of: kind) { setSlot(side, index, nil) }
            }
        }
        if !isPlaced(kind) { hidden.remove(kind) }
    }

    /// Puts an app in the centre, as the phone's app picker does. Where it came from takes the
    /// app that was there, so two apps swap with one pick each way; from nowhere, the old one
    /// goes back with the icons. The centre keeps the side it reaches over.
    public mutating func setCentre(_ kind: HudPanelKind) {
        makeCentre(kind, side: centre?.side)
    }

    private mutating func makeCentre(_ kind: HudPanelKind, side: HudSide?) {
        let old = centre
        if old?.kind == kind {
            bigs[0].side = side
            hidden.remove(kind)
            return
        }
        let swapIn = old?.kind
        switch spot(of: kind) {
        case let .slot(s, index): setSlot(s, index, swapIn)
        case let .row(index): row[index] = swapIn
        case .middle, .off: break
        }
        // The other layout's slots keep their own places, but not a copy of the centre.
        left = left.map { $0 == kind ? nil : $0 }
        right = right.map { $0 == kind ? nil : $0 }
        row = row.map { $0 == kind ? nil : $0 }
        bigs = [Big(kind: kind, side: side)]
        hidden.remove(kind)
        if let swapIn { hidden.remove(swapIn) }
    }

    /// Drops a kind somewhere, as the editor does.
    ///
    /// On the middle, it becomes the centre app (swapping with the one there). On a slot it is a
    /// widget there, and whatever was there swaps into its old slot, or goes back to the icons
    /// if it came from them; the centre itself dropped on a side reaches over that side instead.
    public mutating func place(_ kind: HudPanelKind, at spot: HudSpot) {
        if spot == .off { return remove(kind) }
        if spot == .middle { return makeCentre(kind, side: nil) }
        if isRow { return placeInRow(kind, at: spot) }
        guard case let .slot(side, index) = spot, (0..<Self.slotsPerSide).contains(index) else {
            return
        }
        if centre?.kind == kind {
            bigs[0].side = side
            hidden.remove(kind)
            return
        }
        let from = self.spot(of: kind)
        let occupant = slots(side)[index]
        if occupant == kind { hidden.remove(kind); return }
        if case let .slot(fromSide, fromIndex) = from {
            setSlot(fromSide, fromIndex, occupant)
        } else if let occupant {
            hidden.remove(occupant)
        }
        setSlot(side, index, kind)
        hidden.remove(kind)
    }

    /// The row layout: widgets swapping places along the row. The centre dropped on the row
    /// swaps with the widget there.
    private mutating func placeInRow(_ kind: HudPanelKind, at spot: HudSpot) {
        guard case let .row(index) = spot, row.indices.contains(index) else { return }
        let occupant = row[index]
        if centre?.kind == kind {
            if let occupant { makeCentre(occupant, side: nil) }
            return
        }
        if occupant == kind { hidden.remove(kind); return }
        if let from = row.firstIndex(of: kind) {
            row[from] = occupant
        } else if let occupant {
            hidden.remove(occupant)
        }
        row[index] = kind
        hidden.remove(kind)
    }

    /// A tap: off the glasses for now, keeping its place; or back on.
    public mutating func toggleHidden(_ kind: HudPanelKind) {
        guard isPlaced(kind) else { return }
        if hidden.contains(kind) { hidden.remove(kind) } else { hidden.insert(kind) }
    }
}

extension HudArrangement {
    /// The big panels left to right as placed, whether switched off for now or not: what the
    /// phone's miniature draws.
    public var placedBigsInOrder: [Big] {
        guard let centre else { return [] }
        return [isRow ? Big(kind: centre.kind) : centre]
    }
}

/// The phone's miniature of the glasses: the same columns, squeezed into whatever rectangle the
/// phone has. Widths keep the glasses' proportions; the three rows share the height.
public struct MiniLayout: Sendable {
    public var size: CGSize
    /// The row layout's edge; nil for columns.
    public var strip: HudEdge?

    public init(size: CGSize, strip: HudEdge? = nil) {
        self.size = size
        self.strip = strip
    }

    /// The row layout's band of widgets, as tall as on the glasses for the height given.
    public var rowHeight: CGFloat {
        size.height * GlassesLayout.rowHeight / GlassesLayout.safeFrame.height
    }

    public func rowSlot(_ index: Int) -> CGRect {
        let count = CGFloat(HudArrangement.rowSlots)
        let width = (size.width - gap * (count - 1)) / count
        return CGRect(x: CGFloat(index) * (width + gap), y: strip == .bottom ? size.height - rowHeight : 0,
                      width: width, height: rowHeight)
    }

    public var sideWidth: CGFloat {
        size.width * GlassesLayout.slotWidth / GlassesLayout.safeFrame.width
    }
    public var gap: CGFloat {
        max(4, size.width * GlassesLayout.gap / GlassesLayout.safeFrame.width)
    }
    public var slotHeight: CGFloat { (size.height - gap * 2) / 3 }

    public func slot(_ side: HudSide, _ index: Int) -> CGRect {
        CGRect(x: side == .left ? 0 : size.width - sideWidth,
               y: CGFloat(index) * (slotHeight + gap), width: sideWidth, height: slotHeight)
    }

    public var middle: CGRect {
        if let strip {
            return CGRect(x: 0, y: strip == .top ? rowHeight + gap : 0, width: size.width,
                          height: size.height - rowHeight - gap)
        }
        return CGRect(x: sideWidth + gap, y: 0, width: size.width - (sideWidth + gap) * 2,
               height: size.height)
    }

    /// Where the big panels are drawn: sharing the middle and any side they reach over.
    public func bigFrames(_ arrangement: HudArrangement) -> [(kind: HudPanelKind, frame: CGRect)] {
        let bigs = arrangement.placedBigsInOrder
        guard !bigs.isEmpty else { return [] }
        if strip != nil { return [(bigs[0].kind, middle)] }
        let sides = Set(bigs.compactMap(\.side))
        let minX = sides.contains(.left) ? 0 : sideWidth + gap
        let maxX = sides.contains(.right) ? size.width : size.width - sideWidth - gap
        let width = (maxX - minX - gap * CGFloat(bigs.count - 1)) / CGFloat(bigs.count)
        return bigs.enumerated().map { index, big in
            (big.kind, CGRect(x: minX + CGFloat(index) * (width + gap), y: 0,
                              width: width, height: size.height))
        }
    }

    /// What a drop at a point means: a slot down a side (for a big panel, reaching over that
    /// side), or the middle.
    public func spot(at point: CGPoint) -> HudSpot {
        if strip != nil {
            let band = rowSlot(0)
            guard point.y >= band.minY - gap / 2, point.y <= band.maxY + gap / 2 else { return .middle }
            let width = band.width + gap
            return .row(min(max(Int(point.x / width), 0), HudArrangement.rowSlots - 1))
        }
        let row = min(max(Int(point.y / (slotHeight + gap)), 0), HudArrangement.slotsPerSide - 1)
        if point.x < sideWidth + gap / 2 { return .slot(.left, row) }
        if point.x > size.width - sideWidth - gap / 2 { return .slot(.right, row) }
        return .middle
    }
}

/// One of three ready arrangements the phone switches between. Each keeps its own edits; holding
/// its name puts the preset back.
public struct HudScene: Codable, Equatable, Sendable {
    public var name: String
    public var arrangement: HudArrangement

    public init(name: String, arrangement: HudArrangement) {
        self.name = name
        self.arrangement = arrangement
    }

    public static let count = 3

    public static let presets: [HudScene] = [
        // At a desk: the browser in the centre, the Mac live in a slot to swap in.
        HudScene(name: "DESK", arrangement: HudArrangement(
            left: [.clock, .calendar, .weather], right: [.mac, .music, .note],
            centre: .init(kind: .browser))),
        // Walking: one row of widgets along the top and a single app under it; a tap on the
        // centre's chip takes it away to see the street.
        HudScene(name: "STREET", arrangement: HudArrangement(
            left: [.calendar, .weather, .clock], right: [.music, .activity, .captions],
            centre: .init(kind: .map),
            row: [.clock, .weather, .calendar, .music], strip: .top)),
        // Evening: something to watch, and the sky.
        HudScene(name: "NIGHT", arrangement: HudArrangement(
            left: [.clock, .weather, .sky], right: [.music, .photos, .browser],
            centre: .init(kind: .youtube))),
    ]
}
