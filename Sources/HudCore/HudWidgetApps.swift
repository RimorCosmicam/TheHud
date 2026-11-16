import SwiftUI

// The newer widgets held up alone, each on the canvas inside the safe inset (1792 x 952).
// Positions inside are fixed numbers, as in the Maps app, so clicks can be worked out without
// a view: see `MusicLayout` and `ClockAppLayout`.

/// The safe canvas an app has when held up alone; in the centre it gets less.
public let fullAppSize = CGSize(width: 1792, height: 952)

/// Whether an app has the whole canvas's width or the centre's.
func isWide(_ size: CGSize) -> Bool { size.width >= 1400 }

extension View {
    func appSurface() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(HudTheme.surface,
                        in: RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
                .strokeBorder(HudTheme.edge, lineWidth: 1))
    }

    /// Puts a view at a rect inside the app.
    func at(_ rect: CGRect, alignment: Alignment = .topLeading) -> some View {
        frame(width: rect.width, height: rect.height, alignment: alignment)
            .offset(x: rect.minX, y: rect.minY)
    }
}

// MARK: - Activity

public struct ActivityApp: View {
    public var activity: HudSnapshot.Activity?
    public var size: CGSize
    public init(_ activity: HudSnapshot.Activity?, size: CGSize = fullAppSize) {
        self.activity = activity
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if let activity {
                ZStack {
                    ProgressRing(fraction: activity.fraction, lineWidth: 44)
                    VStack(spacing: 6) {
                        Text(activity.steps.formatted()).font(HudTheme.mont(110, .black))
                            .tracking(-3).lineLimit(1).minimumScaleFactor(0.5)
                        Text("OF \(activity.goal.formatted()) STEPS").font(HudTheme.mont(24, .black))
                            .tracking(3).foregroundStyle(HudTheme.inkDim)
                    }
                    .foregroundStyle(HudTheme.ink)
                    .padding(80)
                }
                .at(isWide(size) ? CGRect(x: 90, y: 156, width: 640, height: 640)
                    : CGRect(x: (size.width - 470) / 2, y: 48, width: 470, height: 470))

                HStack(spacing: 0) {
                    stat("DISTANCE", activity.distanceKm.map { String(format: "%.1f KM", $0) } ?? "--")
                    stat("FLOORS", activity.floors.map(String.init) ?? "--")
                    stat("GOAL", "\(Int(activity.fraction * 100))%")
                }
                .at(isWide(size) ? CGRect(x: 820, y: 150, width: 900, height: 120)
                    : CGRect(x: 56, y: 556, width: size.width - 112, height: 110))

                hours(activity.hourly, bars: isWide(size) ? 260 : 150)
                    .at(isWide(size) ? CGRect(x: 820, y: 420, width: 900, height: 400)
                        : CGRect(x: 56, y: 700, width: size.width - 112, height: 230))
            } else {
                Text("Counting steps needs Motion & Fitness access in Settings")
                    .font(HudTheme.mont(34, .semibold)).foregroundStyle(HudTheme.inkDim)
                    .multilineTextAlignment(.center).padding(40)
                    .at(CGRect(origin: .zero, size: size), alignment: .center)
            }
        }
        .appSurface()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).hudLabel()
            Text(value).font(HudTheme.mont(56, .black)).foregroundStyle(HudTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hours(_ hourly: [Int], bars: CGFloat) -> some View {
        let peak = max(hourly.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 16) {
            Text("BY THE HOUR").hudLabel()
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<24, id: \.self) { hour in
                    let steps = hour < hourly.count ? hourly[hour] : 0
                    let current = hour == hourly.count - 1
                    RoundedRectangle(cornerRadius: 5)
                        .fill(current ? HudTheme.accent : Color.white.opacity(steps > 0 ? 0.55 : 0.1))
                        .frame(height: max(CGFloat(steps) / CGFloat(peak) * bars, 6))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: bars + 10, alignment: .bottom)
            HStack {
                ForEach(["0", "6", "12", "18", "24"], id: \.self) { label in
                    Text(label).font(HudTheme.mont(18, .black)).foregroundStyle(HudTheme.inkFaint)
                    if label != "24" { Spacer() }
                }
            }
        }
    }
}

// MARK: - Music

public struct MusicApp: View {
    public var music: HudSnapshot.NowPlaying?
    public var artwork: Image?
    public var hover: CGPoint?
    public var size: CGSize
    public init(_ music: HudSnapshot.NowPlaying?, artwork: Image?, hover: CGPoint?,
                size: CGSize = fullAppSize) {
        self.music = music
        self.artwork = artwork
        self.hover = hover
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            let wide = isWide(size)
            Artwork(image: artwork, corner: 36)
                .at(wide ? CGRect(x: 72, y: 136, width: 560, height: 560)
                    : CGRect(x: (size.width - 400) / 2, y: 52, width: 400, height: 400))

            VStack(alignment: wide ? .leading : .center, spacing: 14) {
                Text(music?.isPlaying == true ? "NOW PLAYING" : "MUSIC").font(HudTheme.mont(20, .black))
                    .tracking(4).foregroundStyle(music?.isPlaying == true ? HudTheme.accent : HudTheme.inkDim)
                Text(music?.title ?? "Nothing playing").font(HudTheme.mont(wide ? 68 : 52, .black))
                    .lineLimit(wide ? 2 : 1).minimumScaleFactor(0.7).foregroundStyle(HudTheme.ink)
                Text(music?.artist ?? "Play something in the Music app")
                    .font(HudTheme.mont(36, .semibold)).foregroundStyle(HudTheme.ink.opacity(0.85))
                    .lineLimit(1)
                if let album = music?.album, !album.isEmpty {
                    Text(album).font(HudTheme.mont(26, .semibold)).foregroundStyle(HudTheme.inkDim)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(wide ? .leading : .center)
            .at(wide ? CGRect(x: 700, y: 140, width: 1020, height: 360)
                : CGRect(x: 56, y: 470, width: size.width - 112, height: 220),
                alignment: wide ? .bottomLeading : .top)

            if let music {
                VStack(spacing: 12) {
                    ProgressLine(progress: music.progress).frame(height: 8)
                    HStack {
                        Text(HudSnapshot.NowPlaying.time(music.elapsed))
                        Spacer()
                        Text("\u{2212}" + HudSnapshot.NowPlaying.time(max(music.duration - music.elapsed, 0)))
                    }
                    .font(HudTheme.mont(22, .black)).monospacedDigit()
                    .foregroundStyle(HudTheme.inkDim)
                }
                .at(wide ? CGRect(x: 700, y: 540, width: 1020, height: 60)
                    : CGRect(x: 72, y: 700, width: size.width - 144, height: 60))
            }

            ForEach(MusicLayout.buttons(in: size, large: true), id: \.0) { control, frame in
                MusicButton(control: control, isPlaying: music?.isPlaying ?? false, large: true,
                            hovered: hover.map(frame.contains) ?? false)
                    .at(frame)
            }
        }
        .appSurface()
    }
}

// MARK: - Note

/// The note, large: a teleprompter. Scrolling moves it; a click edits it.
public struct NoteApp: View {
    public var note: HudSnapshot.Note
    public var size: CGSize
    public init(_ note: HudSnapshot.Note, size: CGSize = fullAppSize) {
        self.note = note
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            WidgetLabel(text: note.isEditing ? "WRITING" : "NOTE", accent: note.isEditing)
                .at(CGRect(x: 72, y: 56, width: 600, height: 30))
            Group {
                if note.text.isEmpty && !note.isEditing {
                    Text("Click to write a note").foregroundStyle(HudTheme.inkFaint)
                } else {
                    (Text(note.text) + Text(note.isEditing ? "|" : "").foregroundColor(HudTheme.accent))
                        .foregroundStyle(HudTheme.ink)
                }
            }
            .font(HudTheme.mont(isWide(size) ? 64 : 48, .semibold))
            .lineSpacing(14)
            .frame(width: size.width - 232, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: 116, y: 120 - note.scroll)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .appSurface()
    }
}

// MARK: - Captions

public struct CaptionsApp: View {
    public var captions: HudSnapshot.Captions
    public var size: CGSize
    public init(_ captions: HudSnapshot.Captions, size: CGSize = fullAppSize) {
        self.captions = captions
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 18) {
                WidgetLabel(text: "CAPTIONS")
                Spacer()
                Text(captions.isListening ? captions.elapsed : "")
                    .font(HudTheme.mont(22, .black)).foregroundStyle(HudTheme.inkDim)
                Text(captions.isListening ? captions.status : captions.status + " \u{00B7} CLICK TO START")
                    .font(HudTheme.mont(20, .black)).tracking(3)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(captions.isListening ? HudTheme.accent : HudTheme.inkFaint)
            }
            .at(CGRect(x: 72, y: 52, width: size.width - 144, height: 40))

            CaptionLines(captions: captions, size: isWide(size) ? 54 : 44, count: 7)
                .at(CGRect(x: isWide(size) ? 120 : 72, y: 120, width: size.width - (isWide(size) ? 240 : 144),
                           height: size.height - 192), alignment: .bottomLeading)
        }
        .appSurface()
    }
}
