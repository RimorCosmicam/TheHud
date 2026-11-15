#if os(iOS)
import SwiftUI
import MediaPlayer

/// What the Music app is playing, and its buttons. iOS lets an app read and drive the system
/// music player (the Music app) and nothing else, which is why this is Apple Music only.
@MainActor
public final class MusicProvider {
    public var onChange: ((HudSnapshot.NowPlaying?, Image?) -> Void)?
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var started = false
    private var observers: [NSObjectProtocol] = []
    private var artworkFor: String?

    public init() {}

    /// Asks for access the first time the widget is placed, then follows the player.
    public func start() {
        guard !started else { return }
        started = true
        MPMediaLibrary.requestAuthorization { _ in
            Task { @MainActor in self.follow() }
        }
    }

    private func follow() {
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                     .MPMusicPlayerControllerPlaybackStateDidChange] {
            observers.append(center.addObserver(forName: name, object: player, queue: .main) { _ in
                MainActor.assumeIsolated { self.refresh() }
            })
        }
        refresh()
    }

    /// Once a second while playing, for the progress bar.
    public func tick() {
        guard started, player.playbackState == .playing else { return }
        refresh()
    }

    private func refresh() {
        guard let item = player.nowPlayingItem else {
            onChange?(nil, nil)
            return
        }
        let playing = HudSnapshot.NowPlaying(
            title: item.title ?? "Unknown", artist: item.artist ?? "",
            album: item.albumTitle ?? "", isPlaying: player.playbackState == .playing,
            elapsed: player.currentPlaybackTime.isFinite ? player.currentPlaybackTime : 0,
            duration: item.playbackDuration)
        var image: Image?
        if let art = item.artwork?.image(at: CGSize(width: 600, height: 600)) {
            image = Image(uiImage: art)
        }
        onChange?(playing, image)
    }

    public func playPause() {
        if player.playbackState == .playing { player.pause() } else { player.play() }
        refreshSoon()
    }

    public func next() {
        player.skipToNextItem()
        refreshSoon()
    }

    /// Back to the start of the song, or to the one before if it has only just begun.
    public func previous() {
        if player.currentPlaybackTime > 3 { player.skipToBeginning() } else { player.skipToPreviousItem() }
        refreshSoon()
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            self.refresh()
        }
    }
}
#endif
