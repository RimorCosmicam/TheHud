import Foundation

/// One video, as a list shows it.
public struct YouTubeVideo: Sendable, Equatable, Hashable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var channel: String
    /// "11:07", "LIVE", or empty when the page did not say.
    public var duration: String
    /// Views and age, already worded by YouTube: "2.2K views · 3 days ago".
    public var meta: String

    public init(id: String, title: String, channel: String = "", duration: String = "", meta: String = "") {
        self.id = id
        self.title = title
        self.channel = channel
        self.duration = duration
        self.meta = meta
    }

    public var isLive: Bool { duration.uppercased() == "LIVE" }

    /// YouTube's own still for it, 320 by 180.
    public var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")! }
    public var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }

    /// For stills and previews.
    public static let samples: [YouTubeVideo] = [
        .init(id: "s1", title: "Night drive through Tokyo, no talking", channel: "City Walks", duration: "1:12:40", meta: "2.1M views · 3 weeks ago"),
        .init(id: "s2", title: "How birdbath optics work", channel: "Optics Lab", duration: "14:22", meta: "380K views · 5 days ago"),
        .init(id: "s3", title: "Lisbon trams, a whole day", channel: "Slow TV", duration: "LIVE", meta: "1.2K watching"),
        .init(id: "s4", title: "Making bread with one bowl", channel: "Kitchen Notes", duration: "9:05", meta: "90K views · 1 day ago"),
        .init(id: "s5", title: "The quietest place on Earth", channel: "Field Recordings", duration: "22:31", meta: "4.4M views · 2 years ago"),
        .init(id: "s6", title: "Jazz for a rainy afternoon", channel: "Hygge Café", duration: "3:38:14", meta: "728 views · 12 hours ago"),
        .init(id: "s7", title: "Fixing a 1970s synthesizer", channel: "Bench Repairs", duration: "41:10", meta: "212K views · 1 month ago"),
        .init(id: "s8", title: "Starship catch, every angle", channel: "Launch Pad", duration: "11:07", meta: "657K views · 19 hours ago"),
        .init(id: "s9", title: "A walk in the Alfama at dawn", channel: "City Walks", duration: "58:02", meta: "41K views · 6 days ago"),
    ]
}

/// Reads YouTube's pages for the lists the app shows: Home, Subscriptions, search results, and
/// what comes next after a video.
///
/// Every YouTube page carries its content as one JSON object, `ytInitialData`, which the page's
/// script then draws. Reading that is what the page itself does, so it is the steadiest thing to
/// read: the markup around it changes every few weeks, the data far less. Videos come in two
/// shapes, the older `videoRenderer` family and the newer `lockupViewModel`; both are looked for
/// anywhere in the tree, so a reshuffled page still yields its videos. Shorts, playlists, mixes,
/// channels and ads are left out.
public enum YouTubeData {
    public static func videos(inPage html: String) -> [YouTubeVideo] {
        guard let data = initialData(html) else { return [] }
        return videos(in: data)
    }

    /// The `ytInitialData` object in a page's HTML.
    public static func initialData(_ html: String) -> Any? {
        let markers = ["var ytInitialData = ", "window[\"ytInitialData\"] = ", "ytInitialData = "]
        for marker in markers {
            guard let start = html.range(of: marker),
                  let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex)
            else { continue }
            let json = html[start.upperBound..<end.lowerBound]
            if let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) { return object }
        }
        return nil
    }

    public static func videos(in data: Any) -> [YouTubeVideo] {
        var found: [YouTubeVideo] = []
        var seen = Set<String>()
        walk(data) { key, value in
            let video: YouTubeVideo?
            switch key {
            case "videoRenderer", "gridVideoRenderer", "compactVideoRenderer":
                video = renderer(value)
            case "lockupViewModel":
                video = lockup(value)
            default:
                return false
            }
            if let video, !seen.contains(video.id) {
                seen.insert(video.id)
                found.append(video)
            }
            return true
        }
        return found
    }

    // ------------------------------------------------------------------ the two shapes

    private static func renderer(_ value: Any) -> YouTubeVideo? {
        guard let r = value as? [String: Any], let id = r["videoId"] as? String, !id.isEmpty else { return nil }
        let url = dig(r, "navigationEndpoint", "commandMetadata", "webCommandMetadata", "url") as? String ?? ""
        guard !url.contains("/shorts/") else { return nil }
        let title = text(r["title"])
        guard !title.isEmpty else { return nil }
        let channel = [r["ownerText"], r["shortBylineText"], r["longBylineText"]].lazy
            .map(text).first { !$0.isEmpty } ?? ""
        var duration = text(r["lengthText"])
        if duration.isEmpty, let overlays = r["thumbnailOverlays"] as? [[String: Any]] {
            duration = overlays.lazy
                .compactMap { $0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any] }
                .map { text($0["text"]) }.first { !$0.isEmpty } ?? ""
        }
        if duration.isEmpty, let badges = r["badges"] as? [[String: Any]],
           badges.contains(where: { text(($0["metadataBadgeRenderer"] as? [String: Any])?["label"]).uppercased() == "LIVE" }) {
            duration = "LIVE"
        }
        let views = [r["shortViewCountText"], r["viewCountText"]].lazy.map(text).first { !$0.isEmpty } ?? ""
        let meta = [views, text(r["publishedTimeText"])].filter { !$0.isEmpty }.joined(separator: " · ")
        return YouTubeVideo(id: id, title: title, channel: channel, duration: duration.uppercased() == "LIVE" ? "LIVE" : duration,
                            meta: meta)
    }

    private static func lockup(_ value: Any) -> YouTubeVideo? {
        guard let l = value as? [String: Any],
              l["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
              let id = l["contentId"] as? String, !id.isEmpty,
              let metadata = (l["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
        else { return nil }
        let title = text(metadata["title"])
        guard !title.isEmpty else { return nil }
        let rows = (dig(metadata, "metadata", "contentMetadataViewModel", "metadataRows") as? [[String: Any]] ?? [])
            .compactMap { $0["metadataParts"] as? [[String: Any]] }
            .map { $0.map { text($0["text"]) }.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
        var duration = ""
        if let image = l["contentImage"] {
            walk(image) { key, value in
                guard key == "thumbnailBadgeViewModel", duration.isEmpty else { return false }
                let badge = text((value as? [String: Any])?["text"])
                // "New" and the like are labels, not lengths.
                if badge.contains(":") || badge.uppercased() == "LIVE" { duration = badge }
                return true
            }
        }
        return YouTubeVideo(id: id, title: title, channel: rows.first?.first ?? "",
                            duration: duration.uppercased() == "LIVE" ? "LIVE" : duration,
                            meta: rows.dropFirst().first?.joined(separator: " · ") ?? "")
    }

    // ------------------------------------------------------------------ helpers

    private static func dig(_ value: Any?, _ keys: String...) -> Any? {
        keys.reduce(value) { ($0 as? [String: Any])?[$1] }
    }

    /// YouTube's text comes as `simpleText`, as `runs` to join, or as `content`.
    static func text(_ value: Any?) -> String {
        if let s = value as? String { return s }
        guard let d = value as? [String: Any] else { return "" }
        if let s = d["simpleText"] as? String { return s }
        if let s = d["content"] as? String { return s }
        if let runs = d["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    /// Every key in the tree, depth first in document order. `visit` returns true when it has
    /// taken the value, so its insides are not searched again.
    private static func walk(_ value: Any, _ visit: (String, Any) -> Bool) {
        if let d = value as? [String: Any] {
            // Dictionaries have no order; YouTube's lists are arrays, so order survives there.
            for (key, child) in d where !visit(key, child) { walk(child, visit) }
        } else if let a = value as? [Any] {
            for child in a { walk(child, visit) }
        }
    }
}
