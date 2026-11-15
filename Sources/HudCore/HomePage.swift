import Foundation

/// A site on the start page.
public struct Favorite: Codable, Equatable, Sendable {
    public var title: String
    public var url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    /// The site, ignoring scheme, path and a leading www, which is what "is this a favourite"
    /// means to a person: youtube.com/watch?v=… is still YouTube.
    public var site: String { Self.site(of: url) }

    public static func site(of url: String) -> String {
        let host = URL(string: url)?.host ?? URL(string: "https://" + url)?.host ?? url
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static let defaults = [
        Favorite(title: "Google", url: "https://www.google.com"),
        Favorite(title: "YouTube", url: "https://www.youtube.com"),
    ]
}

/// The start page: the favourites, on black.
///
/// Black, not dark grey: on a birdbath display black is the glass, so the page is the tiles
/// floating in the world rather than a lit rectangle in front of it.
public enum HomePage {
    public static func html(_ favorites: [Favorite]) -> String {
        let tiles = favorites.map { favorite -> String in
            let site = escape(favorite.site)
            let letter = escape(String(favorite.title.prefix(1)).uppercased())
            return """
            <a class="tile" href="\(escape(favorite.url))">
              <div class="icon"><span>\(letter)</span>\
            <img src="https://www.google.com/s2/favicons?domain=\(site)&amp;sz=128" alt="" \
            onload="this.parentNode.classList.add('loaded')" onerror="this.remove()"></div>
              <div class="name">\(escape(favorite.title))</div>
            </a>
            """
        }.joined(separator: "\n")

        let empty = favorites.isEmpty
            ? "<p class=\"hint\">Star a site from the phone to keep it here.</p>" : ""

        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="dark">
        <title>Favorites</title>
        <style>
          html, body { margin: 0; background: #000; color: #fff; height: 100%; }
          body { font: 600 22px -apple-system, system-ui, sans-serif; }
          main { max-width: 980px; margin: 0 auto; padding: 22vh 64px 64px; }
          h1 { font-size: 40px; font-weight: 700; margin: 0 0 34px; letter-spacing: -0.5px; }
          .grid { display: flex; flex-wrap: wrap; gap: 34px 30px; }
          .tile { width: 132px; text-decoration: none; color: inherit; text-align: center; }
          .icon { position: relative; width: 132px; height: 132px; border-radius: 30px;
                  background: #1d1d1f; display: flex; align-items: center;
                  justify-content: center; overflow: hidden;
                  box-shadow: inset 0 0 0 1.5px rgba(255,255,255,0.10); }
          .icon span { font-size: 58px; font-weight: 800; color: #d8a628; }
          .icon img { position: absolute; width: 84px; height: 84px; border-radius: 16px; }
          .icon.loaded span { visibility: hidden; }
          .name { margin-top: 14px; font-size: 22px; white-space: nowrap; overflow: hidden;
                  text-overflow: ellipsis; color: rgba(255,255,255,0.88); }
          .hint { color: rgba(255,255,255,0.5); }
        </style>
        </head><body><main>
        <h1>Favorites</h1>
        <div class="grid">
        \(tiles)
        </div>
        \(empty)
        </main></body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
