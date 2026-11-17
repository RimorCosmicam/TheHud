import SwiftUI

// The camera: the phone's own camera seen through the glasses. A viewfinder that takes photos and
// video into the library, and a magnifier: close up, held still, brighter than the room.
//
// The picture itself is the device's (`GlassesScreen.cameraContent`); everything drawn over it,
// and the phone's pad, is here, so both phones and the stills draw the same thing.

extension HudSnapshot {
    public struct Camera: Sendable, Equatable {
        public enum Mode: String, Sendable, CaseIterable {
            case photo, video, magnify

            public var title: String {
                switch self {
                case .photo: return "PHOTO"
                case .video: return "VIDEO"
                case .magnify: return "MAGNIFIER"
                }
            }
        }

        public enum Status: String, Sendable {
            case running
            /// The phone's app is not in front: the camera is the phone's to give, and it gives it
            /// only to the app on screen.
            case paused
            case denied
            /// No camera to open (the stills, a phone without one).
            case unavailable
        }

        public var mode: Mode = .photo
        public var status: Status = .running
        /// Times the widest the lens shows.
        public var zoom: Double = 1
        public var maxZoom: Double = 10
        public var front = false
        public var light = false
        /// Magnifier: the picture brighter than the room, for small print in the dark.
        public var bright = false
        /// Magnifier: the picture held still, to read it with the phone put down.
        public var frozen = false
        public var recordingSince: Date?
        /// When the last photo was taken: the glasses flash.
        public var shotAt: Date = .distantPast
        /// "SAVED TO PHOTOS", or why not, for a few seconds.
        public var notice: String = ""

        public init() {}

        public var isRecording: Bool { recordingSince != nil }

        /// The zoom as it is shown: "1×", "2.5×".
        public var zoomTitle: String {
            let rounded = (zoom * 10).rounded() / 10
            return rounded == rounded.rounded() ? "\(Int(rounded))\u{00D7}" : String(format: "%.1f\u{00D7}", rounded)
        }

        /// The next zoom a step in (positive) or out from here: the stops a camera app has.
        public func zoom(stepping by: Int) -> Double {
            // The lens's own top is a stop too, where it falls between them.
            let stops = [1, 1.5, 2, 3, 4, 6, 8, 10, 15, 20].filter { $0 < maxZoom - 0.01 } + [maxZoom]
            if by > 0 { return stops.first { $0 > zoom + 0.01 } ?? maxZoom }
            return stops.last { $0 < zoom - 0.01 } ?? 1
        }

        /// What the magnifier starts at.
        public static let magnifierZoom: Double = 4

        public static let preview: Camera = {
            var c = Camera()
            c.zoom = 2
            return c
        }()
    }
}

public enum CameraAction: Sendable, Equatable {
    /// A photo, or video started or stopped.
    case shutter
    case mode(HudSnapshot.Camera.Mode)
    /// A stop in (positive) or out.
    case zoom(Int)
    case flip, freeze, light, bright
}

/// Where the camera's picture is on the glasses, and whether it fills the place or fits in it.
public struct CameraPlace: Equatable, Sendable {
    public var frame: CGRect
    public var fill: Bool
    public var corner: CGFloat
}

// MARK: - The picture

/// The picture and what is drawn over it: the mode, the zoom, recording, a flash when a photo is
/// taken, and a card instead when the camera is not running.
struct CameraView: View {
    var camera: HudSnapshot.Camera
    /// The live picture (fill or fit); nil draws a stand-in, or nothing on the device.
    var content: ((Bool) -> AnyView)?
    var standIn: Bool
    var fill: Bool
    /// Widget-sized: fewer, smaller marks.
    var compact: Bool

    var body: some View {
        ZStack {
            Color.black
            if camera.status == .running {
                if let content { content(fill) } else if standIn { CameraStandIn() }
            }
            overlay
            if camera.status != .running { card }
            TimelineView(.animation(minimumInterval: 1 / 30, paused: Date().timeIntervalSince(camera.shotAt) > 0.4)) { context in
                let since = context.date.timeIntervalSince(camera.shotAt)
                Color.white.opacity(since < 0.35 ? 0.8 * (1 - since / 0.35) : 0).allowsHitTesting(false)
            }
        }
        .clipped()
    }

    private var overlay: some View {
        let pad: CGFloat = compact ? 20 : 36
        let size: CGFloat = compact ? 15 : 20
        return ZStack {
            HStack(spacing: 12) {
                if camera.isRecording {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        HStack(spacing: 10) {
                            Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)).frame(width: size * 0.7, height: size * 0.7)
                            Text(Self.duration(context.date.timeIntervalSince(camera.recordingSince ?? context.date)))
                                .monospacedDigit()
                        }
                    }
                } else {
                    Text(camera.mode.title).foregroundStyle(camera.mode == .magnify ? HudTheme.accent : HudTheme.ink)
                }
                if camera.frozen { badge("FROZEN") }
                if camera.light { Image(systemName: "flashlight.on.fill") }
                if camera.bright, camera.mode == .magnify { Image(systemName: "sun.max.fill") }
            }
            .font(HudTheme.mont(size, .black)).tracking(2.5).foregroundStyle(HudTheme.ink)
            .shadow(color: .black.opacity(0.8), radius: 6)
            .padding(pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if !camera.notice.isEmpty, !compact {
                    Text(camera.notice).font(HudTheme.mont(size, .black)).tracking(2)
                        .foregroundStyle(HudTheme.ink)
                }
                Spacer()
                Text(camera.zoomTitle).font(HudTheme.mont(compact ? 18 : 26, .black)).monospacedDigit()
                    .foregroundStyle(camera.zoom > 1.01 ? HudTheme.accent : HudTheme.ink)
            }
            .shadow(color: .black.opacity(0.8), radius: 6)
            .padding(pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(camera.status == .running ? 1 : 0)
    }

    private func badge(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.black)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(HudTheme.accent, in: Capsule())
    }

    private var card: some View {
        let (symbol, title, line): (String, String, String) = {
            switch camera.status {
            case .paused: return ("pause.circle", "CAMERA PAUSED", "Open TheHud on the phone to see through it")
            case .denied: return ("video.slash", "NO CAMERA", "Allow the camera for TheHud in Settings")
            default: return ("video.slash", "NO CAMERA", "This phone has no camera to open")
            }
        }()
        return VStack(spacing: compact ? 10 : 16) {
            Image(systemName: symbol).font(.system(size: compact ? 34 : 54, weight: .light))
                .foregroundStyle(HudTheme.accent)
            Text(title).font(HudTheme.mont(compact ? 18 : 28, .black)).tracking(3).foregroundStyle(HudTheme.ink)
            if !compact {
                Text(line).font(HudTheme.mont(22, .semibold)).foregroundStyle(HudTheme.inkDim)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// The stills' picture: a dim room through a lens, so the marks over it can be seen.
private struct CameraStandIn: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.22), Color(red: 0.06, green: 0.06, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.95, green: 0.78, blue: 0.5).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.7, y: 0.3), startRadius: 0, endRadius: 520)
            GeometryReader { g in
                // A window and a table, as blocks.
                Path { p in
                    p.addRect(CGRect(x: g.size.width * 0.58, y: g.size.height * 0.1,
                                     width: g.size.width * 0.26, height: g.size.height * 0.42))
                }
                .fill(Color.white.opacity(0.12))
                Path { p in
                    p.addRect(CGRect(x: 0, y: g.size.height * 0.7, width: g.size.width, height: g.size.height * 0.3))
                }
                .fill(Color(red: 0.28, green: 0.2, blue: 0.14).opacity(0.7))
            }
        }
    }
}

/// A widget: the picture filling the slot.
public struct CameraWidget: View {
    var camera: HudSnapshot.Camera
    var content: ((Bool) -> AnyView)?
    var standIn: Bool
    public init(_ camera: HudSnapshot.Camera, content: ((Bool) -> AnyView)?, standIn: Bool) {
        self.camera = camera
        self.content = content
        self.standIn = standIn
    }

    public var body: some View {
        CameraView(camera: camera, content: content, standIn: standIn, fill: true, compact: true)
            .clipShape(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
                .strokeBorder(HudTheme.edge, lineWidth: 1))
    }
}

/// The centre, or fullscreen edge to edge: the whole picture, fitted.
public struct CameraApp: View {
    var camera: HudSnapshot.Camera
    var content: ((Bool) -> AnyView)?
    var standIn: Bool
    var corner: CGFloat
    public init(_ camera: HudSnapshot.Camera, content: ((Bool) -> AnyView)?, standIn: Bool, corner: CGFloat) {
        self.camera = camera
        self.content = content
        self.standIn = standIn
        self.corner = corner
    }

    public var body: some View {
        CameraView(camera: camera, content: content, standIn: standIn, fill: false, compact: false)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
