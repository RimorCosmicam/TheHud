import Foundation

public enum HudSide: String, Codable, Sendable, CaseIterable {
    case left, right
}

/// Where something can be dropped in the phone's editor.
public enum HudSpot: Equatable, Sendable {
    case slot(HudSide, Int)
    /// The middle of the glasses: where the browser and the Mac go.
    case middle
    /// Off the glasses: back with the icons.
    case off
}

/// What is on the glasses and where: three widget slots down each side, and the browser and the
/// Mac in the middle, each of which can reach over one side.
///
/// Edited on the phone and saved; the glasses layout is arithmetic over this.
public struct HudArrangement: Codable, Equatable, Sendable {
    public static let slotsPerSide = 3

    public var left: [HudPanelKind?]
    public var right: [HudPanelKind?]
    /// The big panels, in the order they sit in the middle.
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

    public init(left: [HudPanelKind?] = [nil, nil, nil], right: [HudPanelKind?] = [nil, nil, nil],
                bigs: [Big] = [], hidden: Set<HudPanelKind> = []) {
        self.left = Self.padded(left)
        self.right = Self.padded(right)
        self.bigs = bigs
        self.hidden = hidden
    }

    /// The browser in the middle; the clock, the weather and the map down the left.
    public static let standard = HudArrangement(left: [.clock, .weather, .map],
                                                bigs: [Big(kind: .browser)])

    /// Widgets fill the left slots then the right in the usual order; big ones share the middle.
    public init(visible: Set<HudPanelKind>) {
        let widgets = HudPanelKind.widgets.filter(visible.contains).prefix(Self.slotsPerSide * 2)
        let list = Array(widgets)
        self.init(left: Array(list.prefix(3)), right: Array(list.dropFirst(3)),
                  bigs: HudPanelKind.bigs.filter(visible.contains).map { Big(kind: $0) })
    }

    private static func padded(_ slots: [HudPanelKind?]) -> [HudPanelKind?] {
        Array((slots + Array(repeating: nil, count: slotsPerSide)).prefix(slotsPerSide))
    }

    public func slots(_ side: HudSide) -> [HudPanelKind?] { side == .left ? left : right }

    private mutating func setSlot(_ side: HudSide, _ index: Int, _ kind: HudPanelKind?) {
        if side == .left { left[index] = kind } else { right[index] = kind }
    }

    /// Where a kind is now, if it is placed.
    public func spot(of kind: HudPanelKind) -> HudSpot {
        for side in HudSide.allCases {
            if let index = slots(side).firstIndex(of: kind) { return .slot(side, index) }
        }
        return bigs.contains { $0.kind == kind } ? .middle : .off
    }

    public func isPlaced(_ kind: HudPanelKind) -> Bool { spot(of: kind) != .off }
    public func isShown(_ kind: HudPanelKind) -> Bool { isPlaced(kind) && !hidden.contains(kind) }

    /// The side a big panel reaches over, if any.
    public func side(of kind: HudPanelKind) -> HudSide? {
        bigs.first { $0.kind == kind }?.side
    }

    /// The big panels on the glasses, left to right: one reaching over the left first, one
    /// over the right last, the rest in their order between.
    public var orderedBigs: [Big] {
        let shown = bigs.filter { !hidden.contains($0.kind) }
        return shown.filter { $0.side == .left } + shown.filter { $0.side == nil }
            + shown.filter { $0.side == .right }
    }

    /// Sides a shown big panel has taken over.
    public var takenSides: Set<HudSide> {
        Set(orderedBigs.compactMap(\.side))
    }

    /// Widgets that are drawn: placed, not switched off, and not under a big panel.
    public var shownWidgets: [(kind: HudPanelKind, side: HudSide, index: Int)] {
        let taken = takenSides
        return HudSide.allCases.flatMap { side -> [(kind: HudPanelKind, side: HudSide, index: Int)] in
            guard !taken.contains(side) else { return [] }
            return slots(side).enumerated().compactMap { index, kind in
                guard let kind, !hidden.contains(kind) else { return nil }
                return (kind, side, index)
            }
        }
    }

    /// Everything not placed: the icons under the miniature while editing.
    public var unplaced: [HudPanelKind] {
        HudPanelKind.allCases.filter { !isPlaced($0) }
    }

    /// Takes a kind off the glasses.
    public mutating func remove(_ kind: HudPanelKind) {
        for side in HudSide.allCases {
            if let index = slots(side).firstIndex(of: kind) { setSlot(side, index, nil) }
        }
        bigs.removeAll { $0.kind == kind }
        hidden.remove(kind)
    }

    /// Drops a kind somewhere, as the editor does.
    ///
    /// A widget on a slot takes it; whatever was there swaps into the widget's old slot, or goes
    /// back to the icons if the widget came from them. A big panel dropped in the middle sits
    /// there; dropped on a side, it reaches over that side, and a big panel that had that side
    /// goes back to the middle. Big panels never take a slot, and widgets never the middle.
    public mutating func place(_ kind: HudPanelKind, at spot: HudSpot) {
        if spot == .off { return remove(kind) }
        if kind.isBig {
            let side: HudSide?
            switch spot {
            case .middle: side = nil
            case let .slot(s, _): side = s
            case .off: return
            }
            if let side {
                for index in bigs.indices where bigs[index].side == side && bigs[index].kind != kind {
                    bigs[index].side = nil
                }
            }
            if let index = bigs.firstIndex(where: { $0.kind == kind }) {
                bigs[index].side = side
            } else {
                bigs.append(Big(kind: kind, side: side))
            }
            hidden.remove(kind)
            return
        }
        guard case let .slot(side, index) = spot, (0..<Self.slotsPerSide).contains(index) else {
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
        bigs.filter { $0.side == .left } + bigs.filter { $0.side == nil }
            + bigs.filter { $0.side == .right }
    }
}

/// The phone's miniature of the glasses: the same columns, squeezed into whatever rectangle the
/// phone has. Widths keep the glasses' proportions; the three rows share the height.
public struct MiniLayout: Sendable {
    public var size: CGSize

    public init(size: CGSize) { self.size = size }

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
        CGRect(x: sideWidth + gap, y: 0, width: size.width - (sideWidth + gap) * 2,
               height: size.height)
    }

    /// Where the big panels are drawn: sharing the middle and any side they reach over.
    public func bigFrames(_ arrangement: HudArrangement) -> [(kind: HudPanelKind, frame: CGRect)] {
        let bigs = arrangement.placedBigsInOrder
        guard !bigs.isEmpty else { return [] }
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
        let row = min(max(Int(point.y / (slotHeight + gap)), 0), HudArrangement.slotsPerSide - 1)
        if point.x < sideWidth + gap / 2 { return .slot(.left, row) }
        if point.x > size.width - sideWidth - gap / 2 { return .slot(.right, row) }
        return .middle
    }
}
