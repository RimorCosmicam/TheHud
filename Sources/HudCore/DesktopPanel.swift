import SwiftUI

/// The Mac, as HudCast streams it: the whole screen or one window, fitted into the panel
/// without cropping. Clicks and keys on it go to the Mac.
public struct DesktopPanel: View {
    public var desktop: HudSnapshot.Desktop
    public var content: AnyView?
    public var standIn: Bool

    public init(_ desktop: HudSnapshot.Desktop, content: AnyView? = nil, standIn: Bool = false) {
        self.desktop = desktop
        self.content = content
        self.standIn = standIn
    }

    public var body: some View {
        ZStack {
            Color.black
            if let content {
                content
            } else if standIn {
                StandInDesktop()
                    .aspectRatio(desktop.aspect, contentMode: .fit)
            }
            if !desktop.hasPicture && !standIn {
                waiting
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
                .strokeBorder(HudTheme.edge, lineWidth: 1.5)
        )
    }

    private var waiting: some View {
        VStack(spacing: 18) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(HudTheme.accent)
            Text(desktop.status)
                .font(HudTheme.mont(26, .black))
                .tracking(3)
                .foregroundStyle(HudTheme.ink)
            Text(desktop.connected ? "The picture starts in a moment"
                                   : "Open HudCast on your Mac, on the same Wi-Fi")
                .font(HudTheme.mont(24, .semibold))
                .foregroundStyle(HudTheme.inkDim)
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }
}

/// A made-up desktop for stills: a wallpaper, a menu bar and two windows.
struct StandInDesktop: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.10, green: 0.16, blue: 0.32),
                                        Color(red: 0.38, green: 0.20, blue: 0.40)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(.white.opacity(0.18)).frame(height: size.height * 0.035)
                window(title: "Xcode", tint: 0.16)
                    .frame(width: size.width * 0.56, height: size.height * 0.6)
                    .offset(x: size.width * 0.06, y: size.height * 0.12)
                window(title: "Terminal", tint: 0.06)
                    .frame(width: size.width * 0.4, height: size.height * 0.42)
                    .offset(x: size.width * 0.52, y: size.height * 0.46)
            }
        }
    }

    private func window(title: String, tint: Double) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color.red, .yellow, .green], id: \.self) {
                    Circle().fill($0.opacity(0.8)).frame(width: 12, height: 12)
                }
                Spacer()
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(white: tint + 0.1))
            Color(white: tint)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 18)
    }
}
