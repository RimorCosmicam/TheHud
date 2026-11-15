import Foundation
import CoreGraphics
import HudCore

// Reading YouTube's pages, and where clicks land in the YouTube app.

func runYouTubeTests() {
    print("\nYouTube")

    test("search results: videos with length, channel and views; Shorts and live told apart") {
        let html = """
        <script>var ytInitialData = {"contents":{"list":[
          {"videoRenderer":{"videoId":"aaa","title":{"runs":[{"text":"First"}]},
            "ownerText":{"runs":[{"text":"Chan"}]},"lengthText":{"simpleText":"11:07"},
            "shortViewCountText":{"simpleText":"58M views"},"publishedTimeText":{"simpleText":"4 years ago"},
            "navigationEndpoint":{"commandMetadata":{"webCommandMetadata":{"url":"/watch?v=aaa"}}}}},
          {"videoRenderer":{"videoId":"sss","title":{"runs":[{"text":"A Short"}]},
            "navigationEndpoint":{"commandMetadata":{"webCommandMetadata":{"url":"/shorts/sss"}}}}},
          {"videoRenderer":{"videoId":"lll","title":{"simpleText":"Radio"},
            "ownerText":{"runs":[{"text":"Lofi"}]},
            "badges":[{"metadataBadgeRenderer":{"label":"LIVE"}}],
            "viewCountText":{"runs":[{"text":"8.1K"},{"text":" watching"}]}}},
          {"videoRenderer":{"videoId":"aaa","title":{"runs":[{"text":"First again"}]}}}
        ]}};</script>
        """
        let videos = YouTubeData.videos(inPage: html)
        expectEqual(videos.map(\.id), ["aaa", "lll"])
        expectEqual(videos[0].title, "First")
        expectEqual(videos[0].channel, "Chan")
        expectEqual(videos[0].duration, "11:07")
        expectEqual(videos[0].meta, "58M views · 4 years ago")
        expect(videos[1].isLive, "a live stream says so")
        expectEqual(videos[1].meta, "8.1K watching")
    }

    test("Up next: the newer lockup shape, playlists left out, labels are not lengths") {
        let html = """
        <script>var ytInitialData = {"secondary":[
          {"lockupViewModel":{"contentId":"vvv","contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
            "contentImage":{"thumbnailViewModel":{"overlays":[{"b":{"badges":[
              {"thumbnailBadgeViewModel":{"text":"New"}},{"thumbnailBadgeViewModel":{"text":"3:00:01"}}]}}]}},
            "metadata":{"lockupMetadataViewModel":{"title":{"content":"Night Jazz"},
              "metadata":{"contentMetadataViewModel":{"metadataRows":[
                {"metadataParts":[{"text":{"content":"Every Night Jazz"}}]},
                {"metadataParts":[{"text":{"content":"2.2K views"}},{"text":{"content":"3 days ago"}}]}]}}}}}},
          {"lockupViewModel":{"contentId":"PL1","contentType":"LOCKUP_CONTENT_TYPE_PLAYLIST",
            "metadata":{"lockupMetadataViewModel":{"title":{"content":"Mix"}}}}}
        ]};</script>
        """
        let videos = YouTubeData.videos(inPage: html)
        expectEqual(videos.count, 1)
        expectEqual(videos.first?.channel, "Every Night Jazz")
        expectEqual(videos.first?.duration, "3:00:01")
        expectEqual(videos.first?.meta, "2.2K views · 3 days ago")
        expectEqual(videos.first?.thumbnail.absoluteString, "https://i.ytimg.com/vi/vvv/mqdefault.jpg")
    }

    test("a page without YouTube's data gives nothing, not a crash") {
        expect(YouTubeData.videos(inPage: "<html>consent</html>").isEmpty, "empty")
        expect(YouTubeData.videos(inPage: "var ytInitialData = {broken;</script>").isEmpty, "empty")
    }

    test("the app: tabs only offer Subscriptions when it is on; cards count from the scrolled row") {
        var youtube = HudSnapshot.YouTube.preview
        youtube.page = .browse
        expectEqual(youtube.tabs, [.home, .search])
        youtube.showsSubscriptions = true
        expectEqual(youtube.tabs, [.home, .subscriptions, .search])

        let tab = YouTubeAppLayout.tabFrame(1, of: youtube.tabs)
        expectEqual(YouTubeAppLayout.target(at: CGPoint(x: tab.midX, y: tab.midY), youtube), .tab(.subscriptions))
        let card = YouTubeAppLayout.cardFrame(slot: 5)
        expectEqual(YouTubeAppLayout.target(at: CGPoint(x: card.midX, y: card.midY), youtube), .card(5))
        youtube.scrollRow = 1
        expectEqual(YouTubeAppLayout.target(at: CGPoint(x: card.midX, y: card.midY), youtube), nil)
        let first = YouTubeAppLayout.cardFrame(slot: 0)
        expectEqual(YouTubeAppLayout.target(at: CGPoint(x: first.midX, y: first.midY), youtube), .card(4))
        expectEqual(YouTubeAppLayout.maxRow(9), 1)
        expectEqual(YouTubeAppLayout.maxRow(3), 0)
    }

    test("watching: the whole video is one button") {
        var youtube = HudSnapshot.YouTube.preview
        youtube.page = .player
        expectEqual(YouTubeAppLayout.target(at: CGPoint(x: 10, y: 10), youtube), .video)
        expectEqual(YouTubeAppLayout.target(at: CGPoint(x: 1700, y: 900), youtube), .video)
        expectEqual(Array(youtube.sideList.prefix(2)), youtube.queue)
    }
}
