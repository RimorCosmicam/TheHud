#if os(iOS)
import SwiftUI
import WebKit

/// YouTube's own player, and nothing else of its page.
///
/// A web view of its own, apart from the browser's tabs, loading the ordinary watch page with
/// the wearer's sign-in (every `WKWebView` shares the app's one cookie store, so whoever is
/// signed in to YouTube in the browser is signed in here, Premium and all). A style sheet put in
/// before the page draws hides everything but the player and stretches it over the whole view;
/// the HUD draws its own titles, buttons and lists around it.
///
/// The lists themselves are read from YouTube's pages over the network, with the same cookies,
/// by `YouTubeData`.
@MainActor
public final class YouTubePlayer: NSObject, WKNavigationDelegate {
    /// What the page says, once a second.
    public struct State: Equatable, Sendable {
        public var hasVideo = false
        public var videoId = ""
        public var title = ""
        public var channel = ""
        public var isPlaying = false
        public var ended = false
        public var elapsed: Double = 0
        /// Zero while live.
        public var duration: Double = 0
        public var isAd = false
        public var canSkipAd = false
        /// Why there is no picture, when there is none: YouTube's own message, or ours.
        public var notice = ""
    }

    public let webView: WKWebView
    public private(set) var state = State()
    /// Host mode: the Android phone plays the sound (and the picture); this one plays silent.
    public var muted = false {
        didSet { if muted != oldValue { applyMuted() } }
    }
    /// Called whenever the page's state changes.
    public var onChange: ((State) -> Void)?
    private var pollTimer: Timer?
    /// Every frame the video has been put in, newest last. Only one can hold it; when the one
    /// holding it leaves the screen, the newest still on screen takes it.
    private var hosts: [Weak] = []
    private struct Weak { weak var host: WebHostController? }
    private var loadedId = ""
    private var loadedAt = Date()

    public override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // The cursor and the phone are the user; nothing here is ever touched.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.playerOnly, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.overrideUserInterfaceStyle = .dark
        webView.isUserInteractionEnabled = false
        if #available(iOS 16.4, *) {
            // Safari on a Mac can look inside, when something goes wrong on the glasses.
            webView.isInspectable = true
        }
    }

    /// What to say when the page plays no picture.
    private static func notice(_ d: [String: Any], loadedFor seconds: TimeInterval) -> String {
        if let error = d["error"] as? String, !error.isEmpty { return error }
        let hasVideo = d["video"] as? Bool ?? false
        if !hasVideo { return seconds > 10 ? "YouTube showed no player" : "" }
        let width = d["w"] as? Double ?? 0
        let time = d["t"] as? Double ?? 0
        if width == 0 && time > 2 { return "Playing without a picture" }
        return ""
    }

    // ------------------------------------------------------------------ playing

    public func play(_ id: String) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return }
        loadedId = id
        loadedAt = Date()
        state = State()
        state.videoId = id
        state.hasVideo = true
        webView.load(URLRequest(url: url))
        startPolling()
    }

    /// Stops and lets the page go, so nothing plays unseen.
    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        webView.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v){v.pause()})",
                                   completionHandler: nil)
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        loadedId = ""
        state = State()
        onChange?(state)
    }

    public func togglePlay() {
        run("""
        var p = document.getElementById('movie_player'), v = document.querySelector('video');
        if (v) { if (v.paused || v.ended) { p && p.playVideo ? p.playVideo() : v.play(); }
                 else { p && p.pauseVideo ? p.pauseVideo() : v.pause(); } }
        """)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.poll() }
    }

    public func pause() {
        run("var v = document.querySelector('video'); if (v) v.pause();")
    }

    public func seek(by seconds: Double) {
        run("""
        var p = document.getElementById('movie_player'), v = document.querySelector('video');
        if (p && p.seekTo && p.getCurrentTime) { p.seekTo(Math.max(0, p.getCurrentTime() + (\(seconds))), true); }
        else if (v) { v.currentTime = Math.max(0, v.currentTime + (\(seconds))); }
        """)
        state.elapsed = max(0, state.elapsed + seconds)
        onChange?(state)
    }

    public func skipAd() {
        run("""
        var b = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button');
        if (b) b.click();
        """)
    }

    private func run(_ body: String) {
        webView.evaluateJavaScript("(function(){\(body)})();", completionHandler: nil)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// A frame for the video came onto the canvas.
    func register(_ host: WebHostController) {
        hosts.removeAll { $0.host == nil || $0.host === host }
        hosts.append(Weak(host: host))
        host.onWindowChange = { [weak self] in self?.settle() }
    }

    /// Puts the video in the newest frame that is on screen, if the one holding it is not. A
    /// frame going away as another arrives can otherwise take the video with it, leaving the
    /// new frame black.
    func settle() {
        if webView.window != nil, webView.superview?.window != nil { return }
        hosts.removeAll { $0.host == nil }
        guard let host = hosts.last(where: { $0.host?.view.window != nil })?.host else { return }
        host.show(webView, force: true)
    }

    private func applyMuted() {
        run("document.querySelectorAll('video').forEach(function(v){v.muted=\(muted)})")
    }

    private func poll() {
        settle()
        // A new video starts with its own sound: kept as it should be.
        if muted { applyMuted() }
        // While a new page loads, the old one would still answer with the old video.
        guard !loadedId.isEmpty, !webView.isLoading else { return }
        webView.evaluateJavaScript(Self.reading) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self, let json = result as? String,
                      let d = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
                else { return }
                var next = self.state
                next.hasVideo = true
                next.isPlaying = d["playing"] as? Bool ?? false
                next.ended = d["ended"] as? Bool ?? false
                next.isAd = d["ad"] as? Bool ?? false
                next.canSkipAd = next.isAd && (d["skip"] as? Bool ?? false)
                if !next.isAd {
                    next.elapsed = d["t"] as? Double ?? 0
                    next.duration = d["d"] as? Double ?? 0
                }
                // YouTube moved on by itself (its own autoplay): follow.
                if let id = d["id"] as? String, !id.isEmpty, id != next.videoId {
                    next.videoId = id
                    self.loadedId = id
                    next.title = ""
                    next.channel = ""
                }
                if let title = d["title"] as? String, !title.isEmpty, !next.isAd { next.title = title }
                if let channel = d["channel"] as? String, !channel.isEmpty { next.channel = channel }
                next.notice = Self.notice(d, loadedFor: Date().timeIntervalSince(self.loadedAt))
                guard next != self.state else { return }
                self.state = next
                self.onChange?(next)
            }
        }
    }

    // ------------------------------------------------------------------ the page

    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
            decisionHandler(.cancel)
            return
        }
        // Never hand youtube.com to the YouTube app.
        let noAppLink = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2)
        decisionHandler(noAppLink ?? .allow)
    }

    /// Only the player: everything else hidden, the player over the whole view. Applied before
    /// the page draws and kept applied as YouTube rebuilds itself.
    private static let playerOnly = """
    (function () {
      var css =
        'html, body, ytd-app { background: #000 !important; overflow: hidden !important; }' +
        '#masthead-container, ytd-masthead, tp-yt-app-drawer, #guide, #secondary, #below, #chat,' +
        'ytd-miniplayer, ytd-popup-container, tp-yt-iron-overlay-backdrop, #related, #comments,' +
        '.ytp-chrome-top, .ytp-chrome-bottom, .ytp-gradient-top, .ytp-gradient-bottom,' +
        '.ytp-pause-overlay, .ytp-ce-element, .ytp-endscreen-content, .ytp-paid-content-overlay,' +
        '.iv-branding, .ytp-watermark, .ytp-cards-teaser, .ytp-spinner, .ytp-contextmenu,' +
        '.ytp-large-play-button, .ytp-bezel, .ytp-tooltip { display: none !important; }' +
        '#movie_player, #movie_player.html5-video-player { position: fixed !important; left: 0 !important;' +
        ' top: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 2147483646 !important;' +
        ' background: #000 !important; }' +
        // The video's own box has no height of its own (YouTube sizes the video in pixels from
        // script), so a percentage would be of nothing: the viewport is the measure.
        '#movie_player .html5-video-container { position: absolute !important; left: 0 !important;' +
        ' top: 0 !important; width: 100vw !important; height: 100vh !important; }' +
        '#movie_player video, #movie_player video.html5-main-video { position: absolute !important;' +
        ' left: 0 !important; top: 0 !important; width: 100vw !important; height: 100vh !important;' +
        ' object-fit: contain !important; visibility: visible !important; opacity: 1 !important; }';
      function add() {
        if (document.getElementById('__hud_player_only')) return;
        var s = document.createElement('style');
        s.id = '__hud_player_only';
        s.textContent = css;
        (document.head || document.documentElement).appendChild(s);
      }
      add();
      document.addEventListener('DOMContentLoaded', add);
      // The player sizes itself on resize; tell it once it is up.
      var n = 0, t = setInterval(function () {
        add();
        window.dispatchEvent(new Event('resize'));
        if (++n > 10) clearInterval(t);
      }, 700);
    })();
    """

    private static let reading = """
    (function () {
      var p = document.getElementById('movie_player');
      var v = (p && p.querySelector('video')) || document.querySelector('video');
      var skip = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button');
      var ch = document.querySelector('ytd-watch-metadata ytd-channel-name a, #owner #channel-name a, ytd-video-owner-renderer #channel-name a');
      var id = '';
      try { id = new URL(location.href).searchParams.get('v') || ''; } catch (e) {}
      var d = v && isFinite(v.duration) ? v.duration : 0;
      var err = document.querySelector('.ytp-error-content-wrap-reason, .ytp-error .ytp-error-content, yt-playability-error-supported-renderers #reason, ytd-enforcement-message-view-model');
      var errText = err && err.textContent ? err.textContent.trim().replace(/\\s+/g, ' ').slice(0, 120) : '';
      return JSON.stringify({
        video: !!v, w: v ? v.videoWidth : 0, error: errText,
        playing: !!v && !v.paused && !v.ended,
        ended: !!v && v.ended,
        t: v ? v.currentTime : 0, d: d,
        ad: !!(p && (p.classList.contains('ad-showing') || p.classList.contains('ad-interrupting'))),
        skip: !!(skip && skip.offsetParent !== null),
        id: id,
        title: (document.title || '').replace(/^\\(\\d+\\)\\s*/, '').replace(/ - YouTube$/, ''),
        channel: ch ? ch.textContent.trim() : ''
      });
    })();
    """

    // ------------------------------------------------------------------ lists

    public static let homeURL = URL(string: "https://www.youtube.com/")!
    public static let subscriptionsURL = URL(string: "https://www.youtube.com/feed/subscriptions")!

    public static func searchURL(_ query: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        // "sp" asks for videos only: no channels, playlists or Shorts shelves.
        components?.queryItems = [URLQueryItem(name: "search_query", value: query),
                                  URLQueryItem(name: "sp", value: "EgIQAQ==")]
        return components?.url
    }

    /// A YouTube page's videos, fetched as the signed-in wearer. Nil when YouTube could not be
    /// reached; empty when it answered with nothing.
    public static func videos(at url: URL) async -> [YouTubeVideo]? {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            .filter { $0.domain.hasSuffix("youtube.com") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ","),
                         forHTTPHeaderField: "Accept-Language")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        return await Task.detached(priority: .userInitiated) { YouTubeData.videos(inPage: html) }.value
    }
}

/// Puts the player on the canvas. The one web view moves between whichever of these is showing.
public struct YouTubePlayerView: UIViewControllerRepresentable {
    public let player: YouTubePlayer
    public init(_ player: YouTubePlayer) { self.player = player }

    public func makeUIViewController(context: Context) -> WebHostController { WebHostController() }

    public func updateUIViewController(_ host: WebHostController, context: Context) {
        player.register(host)
        host.show(player.webView)
    }
}
#endif
