import SwiftUI

// The newer widgets held up alone, each on the canvas inside the safe inset (1792 x 952).
// Positions inside are fixed numbers, as in the Maps app, so clicks can be worked out without
// a view: see `MusicLayout` and `ClockAppLayout`.

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
    public init(_ activity: HudSnapshot.Activity?) { self.activity = activity }

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
                .at(CGRect(x: 90, y: 156, width: 640, height: 640))

                HStack(spacing: 0) {
                    stat("DISTANCE", activity.distanceKm.map { String(format: "%.1f KM", $0) } ?? "--")
                    stat("FLOORS", activity.floors.map(String.init) ?? "--")
                    stat("GOAL", "\(Int(activity.fraction * 100))%")
                }
                .at(CGRect(x: 820, y: 150, width: 900, height: 120))

                hours(activity.hourly)
                    .at(CGRect(x: 820, y: 420, width: 900, height: 400))
            } else {
                Text("Counting steps needs Motion & Fitness access in Settings")
                    .font(HudTheme.mont(34, .semibold)).foregroundStyle(HudTheme.inkDim)
                    .at(CGRect(x: 0, y: 0, width: 1792, height: 952), alignment: .center)
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

    private func hours(_ hourly: [Int]) -> some View {
        let peak = max(hourly.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 16) {
            Text("BY THE HOUR").hudLabel()
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<24, id: \.self) { hour in
                    let steps = hour < hourly.count ? hourly[hour] : 0
                    let current = hour == hourly.count - 1
                    RoundedRectangle(cornerRadius: 5)
                        .fill(current ? HudTheme.accent : Color.white.opacity(steps > 0 ? 0.55 : 0.1))
                        .frame(height: max(CGFloat(steps) / CGFloat(peak) * 260, 6))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 270, alignment: .bottom)
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
    public init(_ music: HudSnapshot.NowPlaying?, artwork: Image?, hover: CGPoint?) {
        self.music = music
        self.artwork = artwork
        self.hover = hover
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Artwork(image: artwork, corner: 36)
                .at(CGRect(x: 72, y: 136, width: 560, height: 560))

            VStack(alignment: .leading, spacing: 14) {
                Text(music?.isPlaying == true ? "NOW PLAYING" : "MUSIC").font(HudTheme.mont(20, .black))
                    .tracking(4).foregroundStyle(music?.isPlaying == true ? HudTheme.accent : HudTheme.inkDim)
                Text(music?.title ?? "Nothing playing").font(HudTheme.mont(68, .black))
                    .lineLimit(2).foregroundStyle(HudTheme.ink)
                Text(music?.artist ?? "Play something in the Music app")
                    .font(HudTheme.mont(36, .semibold)).foregroundStyle(HudTheme.ink.opacity(0.85))
                    .lineLimit(1)
                if let album = music?.album, !album.isEmpty {
                    Text(album).font(HudTheme.mont(26, .semibold)).foregroundStyle(HudTheme.inkDim)
                        .lineLimit(1)
                }
            }
            .at(CGRect(x: 700, y: 140, width: 1020, height: 360), alignment: .bottomLeading)

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
                .at(CGRect(x: 700, y: 540, width: 1020, height: 60))
            }

            ForEach(MusicLayout.buttons(in: CGSize(width: 1792, height: 952), large: true), id: \.0) { control, frame in
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
    public init(_ note: HudSnapshot.Note) { self.note = note }

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
            .font(HudTheme.mont(64, .semibold))
            .lineSpacing(14)
            .frame(width: 1560, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: 116, y: 120 - note.scroll)
        }
        .clipped()
        .appSurface()
    }
}

// MARK: - Captions

public struct CaptionsApp: View {
    public var captions: HudSnapshot.Captions
    public init(_ captions: HudSnapshot.Captions) { self.captions = captions }

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
            .at(CGRect(x: 72, y: 52, width: 1648, height: 40))

            CaptionLines(captions: captions, size: 54, count: 7)
                .at(CGRect(x: 120, y: 120, width: 1552, height: 760), alignment: .bottomLeading)
        }
        .appSurface()
    }
}
