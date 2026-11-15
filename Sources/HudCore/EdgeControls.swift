import SwiftUI

public enum EdgeControlSide: Sendable { case left, right }

/// MiniMate's single-hand edge controls, ported 1:1.
///
/// "Low-profile single-hand controls that reserve only two narrow edge hit regions. The rail and
/// corner mirror as a pair so the click target is always opposite the scroll hand."
///
/// Android `dp` and SwiftUI points are the same unit for this purpose, so every measurement below
/// is the number MiniMate uses. The CRYSTAL material is the pair of gradients plus the three
/// hairlines — an inner edge line with a white accent just outside it and a cyan accent just
/// inside, which is what gives it the split-light look at a glance.
public struct EdgeControlsOverlay: View {
    public var railEnabled: Bool
    public var rightClickEnabled: Bool
    public var railSide: EdgeControlSide
    public var railScale: CGFloat
    public var cornerScale: CGFloat
    /// Held state, so a still can show the active treatment.
    public var railActive: Bool
    public var cornerPressed: Bool

    public init(railEnabled: Bool = true,
                rightClickEnabled: Bool = true,
                railSide: EdgeControlSide = .left,
                railScale: CGFloat = 1.32,
                cornerScale: CGFloat = 1.28,
                railActive: Bool = false,
                cornerPressed: Bool = false) {
        self.railEnabled = railEnabled
        self.rightClickEnabled = rightClickEnabled
        self.railSide = railSide
        self.railScale = railScale
        self.cornerScale = cornerScale
        self.railActive = railActive
        self.cornerPressed = cornerPressed
    }

    private static let accentWhite = Color.white
    private static let accentCyan = Color(red: 0xD8 / 255, green: 0xF8 / 255, blue: 0xFF / 255)
    private static let railCyan = Color(red: 0xCB / 255, green: 0xF7 / 255, blue: 0xFF / 255)

    private var clampedRail: CGFloat { min(max(railScale, 0.65), 1.8) }
    private var clampedCorner: CGFloat { min(max(cornerScale, 0.65), 1.8) }

    /// The reserved hit region. Wider than the visual on purpose: the rail is swept by a thumb
    /// that does not look at it.
    public var railHitWidth: CGFloat { 52 * clampedRail }
    public var railVisualWidth: CGFloat { (railActive ? 32 : 28) * clampedRail }
    public var cornerBoxSize: CGFloat { 104 * clampedCorner }

    public var body: some View {
        ZStack {
            if railEnabled { rail }
            if rightClickEnabled { corner }
        }
    }

    // ------------------------------------------------------------------ rail

    private var rail: some View {
        let boost: Double = railActive ? 1.75 : 1.0
        let leftToRight: [Color] = [
            .white.opacity(0.018 * boost),
            .white.opacity(0.038 * boost),
            Self.railCyan.opacity(0.026 * boost),
            .clear,
            .white.opacity(0.014 * boost),
        ]
        let horizontal = railSide == .left ? leftToRight : leftToRight.reversed()

        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: horizontal),
                                               startPoint: .zero,
                                               endPoint: CGPoint(x: size.width, y: 0)))

            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(
                            Gradient(colors: [
                                .white.opacity(railActive ? 0.10 : 0.045),
                                .clear,
                                .clear,
                                .white.opacity(railActive ? 0.08 : 0.035),
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: size.height)))

            // The inner edge, then the two accents straddling it 1.4pt either way.
            let innerX = railSide == .left ? size.width : 0
            let outward: CGFloat = railSide == .left ? -1.4 : 1.4

            func line(_ x: CGFloat, _ color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }

            line(innerX, .white.opacity(railActive ? 0.24 : 0.12))
            line(innerX + outward, Self.accentWhite.opacity(railActive ? 0.20 : 0.09))
            line(innerX - outward, Self.accentCyan.opacity(railActive ? 0.16 : 0.065))
        }
        .frame(width: railVisualWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: railSide == .left ? .leading : .trailing)
        .allowsHitTesting(false)
    }

    // ---------------------------------------------------------------- corner

    /// "The right-click corner is always opposite the rail."
    private var cornerOnLeft: Bool { railSide == .right }

    private var corner: some View {
        let boost: Double = cornerPressed ? 1.8 : 1.0
        let radius = (cornerPressed ? 100 : 94) * clampedCorner

        return Canvas { context, size in
            let center = cornerOnLeft ? CGPoint.zero : CGPoint(x: size.width, y: 0)
            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                              width: radius * 2, height: radius * 2))

            context.fill(disc, with: .radialGradient(
                Gradient(colors: [
                    .white.opacity(0.045 * boost),
                    .white.opacity(0.022 * boost),
                    Color(red: 0xD9 / 255, green: 0xF8 / 255, blue: 0xFF / 255).opacity(0.012 * boost),
                    .clear,
                ]),
                center: center, startRadius: 0, endRadius: radius))

            context.stroke(disc, with: .color(.white.opacity(cornerPressed ? 0.28 : 0.14)),
                           lineWidth: 1)

            // Two more rings, nudged 1.4pt apart, splitting the edge into white and cyan.
            let inward: CGFloat = cornerOnLeft ? 1.4 : -1.4
            func ring(_ dx: CGFloat, _ color: Color) {
                let r = radius - 0.4
                let c = CGPoint(x: center.x + dx, y: center.y)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                      width: r * 2, height: r * 2)),
                               with: .color(color), lineWidth: 1)
            }
            ring(inward, Self.accentWhite.opacity(cornerPressed ? 0.20 : 0.09))
            ring(-inward, Self.accentCyan.opacity(cornerPressed ? 0.16 : 0.065))
        }
        .frame(width: cornerBoxSize, height: cornerBoxSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: cornerOnLeft ? .topLeading : .topTrailing)
        .clipped()
        .allowsHitTesting(false)
    }
}
