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
    /// The live `WKWebView` on the device, a still in the preview, nothing at all before the
    /// first page loads. Type-erased because those are genuinely different views.
    public var content: AnyView?
    /// Draw the stand-in page when there is no content. Stills only.
    public var standIn: Bool

    public init(_ browser: HudSnapshot.Browser, content: AnyView? = nil, standIn: Bool = true) {
        self.browser = browser
        self.content = content
        self.standIn = standIn
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabs
            addressBar
            Rectangle().fill(.white.opacity(0.12)).frame(height: BrowserMetrics.dividerHeight)
            Group {
                if let content {
                    content
                } else if standIn {
                    PageStandIn()
                } else {
                    Color(red: 0.07, green: 0.07, blue: 0.08)
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
                    .frame(maxWidth: 620)
                    .frame(height: BrowserMetrics.tabHeight)
                    .background(active ? Color.white.opacity(0.08) : .clear)
                    .overlay(alignment: .bottom) {
                        // State by brightness, and one accent rule under the live tab.
                        Rectangle().fill(active ? HudTheme.accent : .clear).frame(height: 3)
                    }
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
        .frame(height: BrowserMetrics.tabHeight)
    }

    /// Every control here is a fixed-width cell, in the order and at the widths `GlassesLayout`
    /// hit-tests against. A click is the phone's cursor landing on a canvas the phone cannot see,
    /// so what is drawn and what is clickable have to be the same arithmetic.
    private var addressBar: some View {
        HStack(spacing: 0) {
            navIcon("chevron.left", enabled: browser.canGoBack)
                .frame(width: BrowserMetrics.navButtonWidth)
            navIcon("chevron.right", enabled: browser.canGoForward)
                .frame(width: BrowserMetrics.navButtonWidth)

            HStack(spacing: 12) {
                Image(systemName: browser.isEditingAddress ? "magnifyingglass" : "lock.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(HudTheme.inkDim)
                if browser.isEditingAddress {
                    // The caret is the accent, so it is obvious from across the canvas that the
                    // keyboard is talking to this field and not to the page.
                    (Text(browser.url).foregroundColor(HudTheme.ink)
                        + Text("\u{258F}").foregroundColor(HudTheme.accent))
                        .font(HudTheme.mont(22, .black))
                        .tracking(0.5)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text(browser.url)
                        .font(HudTheme.mont(22, .black))
                        .tracking(0.5)
                        .foregroundStyle(HudTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: BrowserMetrics.fieldHeight)
            .background(.white.opacity(browser.isEditingAddress ? 0.14 : 0.08))
            .padding(.horizontal, BrowserMetrics.fieldGap)

            navIcon("arrow.clockwise", enabled: true)
                .frame(width: BrowserMetrics.reloadWidth)
        }
        .padding(.horizontal, BrowserMetrics.sidePadding)
        .frame(height: BrowserMetrics.addressHeight)
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

    private func navIcon(_ symbol: String, enabled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(enabled ? HudTheme.inkDim : HudTheme.inkFaint)
            .frame(maxHeight: .infinity)
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
