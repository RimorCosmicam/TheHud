import SwiftUI
import CoreGraphics

/// The browser.
///
/// Safari's compact layout: the page fills the panel and one glass bar floats over its top edge.
/// At rest the bar is just the page's title. Put the cursor on it and back, forward and reload
/// fade in at its ends; click the title and it becomes the address field. Scroll, and the page
/// slides up under the glass.
///
/// In the app the page is a live `WKWebView` — the only way anything that is not ours can reach
/// the canvas, since iOS will not host another app inside this one. The preview passes a still
/// instead, by the same arrangement `TrackpadSurface` uses for the Metal surface.
///
/// The page is rendered dark on purpose. A white page is the brightest thing a birdbath display
/// can produce, and on the Air it both blinds and destroys the transparency that makes a HUD
/// wearable.
public struct BrowserPanel: View {
    public var browser: HudSnapshot.Browser
    /// The live `WKWebView` on the device, a still in the preview, nothing before the first page
    /// loads. Type-erased because those are genuinely different views.
    public var content: AnyView?
    /// Draw the stand-in page when there is no content. Stills only.
    public var standIn: Bool
    /// The cursor is on the bar.
    public var hovering: Bool
    /// A real backdrop blur. Off for stills: `ImageRenderer` cannot sample what is behind a
    /// material, so the preview gets a tinted stand-in with the same weight.
    public var liveGlass: Bool

    public init(_ browser: HudSnapshot.Browser, content: AnyView? = nil, standIn: Bool = true,
                hovering: Bool = false, liveGlass: Bool = false) {
        self.browser = browser
        self.content = content
        self.standIn = standIn
        self.hovering = hovering
        self.liveGlass = liveGlass
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BrowserMetrics.panelRadius, style: .continuous)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let content {
                    content
                } else if standIn {
                    PageStandIn()
                } else {
                    Color.black
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bar
                .padding(.horizontal, BrowserMetrics.barInset)
                .padding(.top, BrowserMetrics.barInset)
        }
        .background(Color.black)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1.5))
    }

    // ------------------------------------------------------------------ bar

    private var showsButtons: Bool { hovering && !browser.isEditingAddress }

    private var bar: some View {
        ZStack {
            if browser.isEditingAddress {
                field
            } else {
                titleLabel
                    // Room for the buttons either side, so they fade in over empty glass
                    // rather than on top of the words.
                    .padding(.horizontal, BrowserMetrics.buttonWidth * 2)
            }

            HStack(spacing: 0) {
                navIcon("chevron.left", enabled: browser.canGoBack)
                navIcon("chevron.right", enabled: browser.canGoForward)
                Spacer(minLength: 0)
                navIcon(browser.loading == nil ? "arrow.clockwise" : "xmark", enabled: true)
            }
            .opacity(showsButtons ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: showsButtons)
        }
        .frame(height: BrowserMetrics.barHeight)
        .background { glass }
        .overlay(alignment: .bottom) { progress }
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(colors: [.white.opacity(hovering ? 0.38 : 0.26), .white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1.5))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 8)
    }

    @ViewBuilder
    private var glass: some View {
        if liveGlass {
            ZStack {
                Rectangle().fill(.thinMaterial)
                // Material alone reads grey on a birdbath; a little black keeps it a tint.
                Color.black.opacity(0.3)
            }
        } else {
            Color(white: 0.10).opacity(0.94)
        }
    }

    private var titleText: String {
        // Safari's start page: the bar is an invitation to type, not a title.
        if browser.isHome { return "Search or enter website name" }
        if !browser.title.isEmpty { return browser.title }
        return browser.url.isEmpty ? "New page" : browser.url
    }

    private var titleLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: browser.isHome ? "magnifyingglass"
                  : browser.isFavorite ? "star.fill" : "globe")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(browser.isFavorite && !browser.isHome
                                 ? HudTheme.accent : HudTheme.inkDim)
            Text(titleText)
                .font(HudTheme.mont(24, .semibold))
                .foregroundStyle(HudTheme.ink.opacity(browser.isHome ? 0.55 : hovering ? 1 : 0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var field: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HudTheme.inkDim)
            // The caret is the accent, so it is obvious from across the canvas that the keyboard
            // is talking to this field and not to the page.
            Group {
                if browser.url.isEmpty {
                    Text("\u{258F}").foregroundColor(HudTheme.accent)
                        + Text("Search Google or enter address").foregroundColor(HudTheme.inkFaint)
                } else {
                    Text(browser.url).foregroundColor(HudTheme.ink)
                        + Text("\u{258F}").foregroundColor(HudTheme.accent)
                }
            }
            .font(HudTheme.mont(24, .semibold))
            .lineLimit(1)
            .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
    }

    @ViewBuilder
    private var progress: some View {
        if let progress = browser.loading {
            GeometryReader { geometry in
                Rectangle().fill(HudTheme.accent)
                    .frame(width: geometry.size.width * progress, height: 3)
            }
            .frame(height: 3)
        }
    }

    private func navIcon(_ symbol: String, enabled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(enabled ? HudTheme.ink : HudTheme.inkFaint)
            .frame(width: BrowserMetrics.buttonWidth, height: BrowserMetrics.barHeight)
    }
}

/// A stand-in page, so a still shows the panel doing its job. Never on the device's path.
public struct PageStandIn: View {
    /// How far the page has been scrolled, so a still can show it passing under the glass.
    public var scrolled: CGFloat

    public init(scrolled: CGFloat = 0) { self.scrolled = scrolled }

    public var body: some View {
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
        .padding(.top, BrowserMetrics.contentTopInset + 26 - scrolled)
        .padding(.bottom, 44)
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
