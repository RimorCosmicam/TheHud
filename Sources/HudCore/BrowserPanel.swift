import SwiftUI
import CoreGraphics

/// The browser.
///
/// This draws the chrome only. In the app the content area holds a live `WKWebView`, which is the
/// whole reason a browser is reachable at all on iOS — there is no way to put another app inside
/// this one, so anything that is not ours has to arrive as a web view. The preview passes a still
/// instead, by the same arrangement `TrackpadSurface` uses for the Metal surface.
///
/// The page is rendered dark on purpose. A white page is the brightest thing a birdbath display
/// can produce, and on the Air it both blinds and destroys the transparency that makes a HUD
/// wearable. The app forces a dark colour scheme and offers reader mode for pages that fight it.
public struct BrowserPanel: View {
    public var browser: HudSnapshot.Browser
    public var content: Image?

    public init(_ browser: HudSnapshot.Browser, content: Image? = nil) {
        self.browser = browser
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabs
            addressBar
            Divider().overlay(.white.opacity(0.12))
            Group {
                if let content {
                    content.resizable().aspectRatio(contentMode: .fill)
                } else {
                    PageStandIn()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(HudTheme.surface)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Array(browser.tabs.enumerated()), id: \.offset) { index, tab in
                let active = index == browser.activeTab
                Text(tab)
                    .font(HudTheme.mont(18, .black))
                    .tracking(2)
                    .foregroundStyle(active ? HudTheme.ink : HudTheme.inkFaint)
                    .lineLimit(1)
                    .padding(.horizontal, 26)
                    .frame(height: 54)
                    .background(active ? Color.white.opacity(0.08) : .clear)
                    .overlay(alignment: .bottom) {
                        // State by brightness, and one accent rule under the live tab.
                        Rectangle().fill(active ? HudTheme.accent : .clear).frame(height: 3)
                    }
            }
            Spacer(minLength: 0)
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(HudTheme.inkFaint)
                .frame(width: 54, height: 54)
        }
        .frame(height: 54)
    }

    private var addressBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right").foregroundStyle(HudTheme.inkFaint)
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(HudTheme.inkDim)

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(HudTheme.inkDim)
                Text(browser.url)
                    .font(HudTheme.mont(22, .black))
                    .tracking(0.5)
                    .foregroundStyle(HudTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            .background(.white.opacity(0.08))

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HudTheme.inkDim)
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
        .overlay(alignment: .bottom) {
            if let progress = browser.loading {
                GeometryReader { geometry in
                    Rectangle().fill(HudTheme.accent)
                        .frame(width: geometry.size.width * progress, height: 3)
                }
                .frame(height: 3)
            }
        }
    }
}

/// A stand-in page, so a still shows the panel doing its job. Never on the device's path.
struct PageStandIn: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UIKit")
                .font(HudTheme.mont(52, .black)).tracking(-1)
                .foregroundStyle(HudTheme.ink)
                .padding(.bottom, 10)

            Text("FRAMEWORK")
                .font(HudTheme.mont(16, .black)).tracking(3)
                .foregroundStyle(HudTheme.accent)
                .padding(.bottom, 26)

            Text("Construct and manage a graphical, event-driven user interface for your iOS, "
                 + "iPadOS, or tvOS app.")
                .font(HudTheme.mont(25, .regular))
                .foregroundStyle(HudTheme.ink.opacity(0.88))
                .lineSpacing(9)
                .padding(.bottom, 34)

            Text("OVERVIEW")
                .font(HudTheme.mont(17, .black)).tracking(3)
                .foregroundStyle(HudTheme.inkDim)
                .padding(.bottom, 16)

            ForEach(0..<4, id: \.self) { row in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.14))
                    .frame(height: 15)
                    .frame(maxWidth: row == 3 ? 420 : .infinity)
                    .padding(.bottom, 15)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 54)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A dark page, not a white one. See the note on BrowserPanel.
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
    }
}

/// The pointer the trackpad drives. Outlined so it survives both the darkest panel and the
/// brightest thing the world puts behind the glass.
struct Cursor: View {
    var body: some View {
        Canvas { context, _ in
            var arrow = Path()
            arrow.move(to: CGPoint(x: 0, y: 0))
            arrow.addLine(to: CGPoint(x: 0, y: 30))
            arrow.addLine(to: CGPoint(x: 8, y: 23))
            arrow.addLine(to: CGPoint(x: 13, y: 34))
            arrow.addLine(to: CGPoint(x: 19, y: 31))
            arrow.addLine(to: CGPoint(x: 14, y: 21))
            arrow.addLine(to: CGPoint(x: 23, y: 20))
            arrow.closeSubpath()
            context.stroke(arrow, with: .color(.black.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            context.fill(arrow, with: .color(.white))
        }
        .frame(width: 26, height: 38)
    }
}
