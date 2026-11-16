import Foundation
import HudCore

// Remote Connect: the pairing code, the proof, and the Android phone's messages.

func runRemoteConnectTests() {
    print("\nRemote Connect")

    test("the QR code's link: id, key in base64url, address and port") {
        let key = Data((0..<32).map { UInt8($0 * 7 & 0xFF) })
        let k = key.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let pairing = RemotePairing(link: "thehud://connect?id=8bc0312a&k=\(k)&h=192.168.1.12&p=47825")
        expectEqual(pairing?.id, "8bc0312a")
        expectEqual(pairing?.key, key)
        expectEqual(pairing?.host, "192.168.1.12")
        expectEqual(pairing?.port, 47825)
        expectEqual(pairing?.serviceName, "TheHud-8bc0312a")
        // Off Wi-Fi the address is empty: Bonjour finds the phone instead.
        expectEqual(RemotePairing(link: "thehud://connect?id=a&k=\(k)&h=&p=1")?.host, "")
        expect(RemotePairing(link: "https://connect?id=a&k=\(k)") == nil, "only thehud links")
        expect(RemotePairing(link: "thehud://connect?id=a&k=AAAA") == nil, "a key too short to be one")
        expect(RemotePairing(link: "thehud://connect?k=\(k)") == nil, "no id")
    }

    test("the proof is HMAC-SHA256 of the challenge under the key (RFC 4231 case 2)") {
        let pairing = RemotePairing(id: "x", key: Data("Jefe".utf8), host: "", port: 1)
        let proof = pairing.proof(for: Data("what do ya want for nothing?".utf8))
        expectEqual(proof.map { String(format: "%02x", $0) }.joined(),
                    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    test("buttons become the Android phone's actions; this phone's own stay here") {
        let place = RemoteWire.message(for: .place(.clock, .slot(.right, 2)))
        expectEqual(place?["a"] as? String, "place")
        expectEqual(place?["spot"] as? String, "right:2")
        expectEqual(RemoteWire.message(for: .scene(1))?["i"] as? Int, 1)
        expectEqual(RemoteWire.message(for: .music(.playPause))?["c"] as? String, "playPause")
        expectEqual(RemoteWire.message(for: .timer(.set(minutes: 10)))?["m"] as? Int, 10)
        expectEqual(RemoteWire.message(for: .selectWindow(nil))?["i"] as? Int, -1)
        expectEqual(RemoteWire.message(for: .sky(.toggle(.milkyWay)))?["layer"] as? String, "milkyWay")
        expect(RemoteWire.message(for: .settings) == nil)
        expect(RemoteWire.message(for: .editGlasses(true)) == nil)
        expect(RemoteWire.message(for: .pad(.touchpad)) == nil)
        // Any app in the centre, and the new apps' buttons, act on the Android phone.
        expectEqual(RemoteWire.message(for: .centre(.photos))?["kind"] as? String, "photos")
        expectEqual(RemoteWire.message(for: .prompter(.faster))?["c"] as? String, "faster")
        expectEqual(RemoteWire.message(for: .photos(.step(-1)))?["by"] as? Int, -1)
        expectEqual(RemoteWire.message(for: .photos(.open))?["c"] as? String, "open")
        expectEqual(RemoteWire.centreCursor()["g"] as? String, "centre")
        let move = RemoteWire.message(for: GestureEvent.move(dx: 3, dy: -4, isDragging: true))
        expectEqual(move["g"] as? String, "move")
        expectEqual(move["dy"] as? Int, -4)
        expectEqual(move["drag"] as? Bool, true)
        expectEqual(RemoteWire.message(for: GestureEvent.rightClick)["g"] as? String, "right")
        // One line each, so the other end can read them with a line reader.
        let line = RemoteWire.line(["t": "submit"])!
        expectEqual(line.last, 0x0A)
        expectEqual(line.filter { $0 == 0x0A }.count, 1)
    }

    test("the Android phone's state, as it sends it") {
        // A line the Android app sent, trimmed.
        let line = """
        {"t":"state","arrangement":{"left":["clock","weather","map"],"right":["music","captions","youtube"],\
        "bigs":[{"kind":"browser","side":null},{"kind":"mac","side":null}],"hidden":["mac","music"],\
        "row":[null,null,null,null],"strip":null},"solo":"sky","clearView":false,"scene":1,\
        "scenes":["DESK","STREET","NIGHT"],"glasses":true,"keyboard":"note","draft":"Milk",\
        "browser":{"tabs":["New Tab","Wikipedia"],"activeTab":1,"canGoBack":true,"canGoForward":false,\
        "isHome":false,"isFavorite":true,"url":"https://en.wikipedia.org","title":"Wikipedia"},\
        "music":{"title":"Song","artist":"Band","album":"","isPlaying":true,"elapsed":12.5,"duration":200},\
        "timer":{"text":"4:59","progress":0.25,"state":"running","isStopwatch":false},\
        "note":{"text":"Milk","isEditing":true},\
        "captions":{"isListening":false,"lines":["Hello"],"partial":"","status":"OFF","elapsed":""},\
        "youtube":{"hasVideo":true,"videoId":"v1","title":"T","channel":"C","isPlaying":false,"isLive":false,\
        "elapsed":3,"duration":60,"isAd":false,"canSkipAd":false,"notice":"","page":"player","tab":"search",\
        "showsSubscriptions":false,"query":"cats","isEditingQuery":false,"home":[],"subscriptions":[],\
        "results":[{"id":"r1","title":"Cats","channel":"Ch","duration":"1:00","meta":"1K views"}],"upNext":[],"queue":[]},\
        "photos":{"hasAccess":true,"count":248,"current":3,"selected":7,"scrollRow":1,"viewing":true,"caption":"12 OCTOBER 2026"},\
        "prompter":{"isRunning":true,"speed":120}}
        """
        let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
        let s = RemoteWire.state(from: object)
        expectEqual(s.arrangement.left, [.clock, .weather, .map])
        expectEqual(s.arrangement.centre?.kind, .browser)
        expect(s.arrangement.hidden.contains(.music))
        expectEqual(s.solo, .sky)
        expectEqual(s.scene, 1)
        expectEqual(s.scenes, ["DESK", "STREET", "NIGHT"])
        expect(s.glassesConnected)
        expectEqual(s.keyboard, "note")
        expectEqual(s.draft, "Milk")
        expectEqual(s.browser.tabs, ["New Tab", "Wikipedia"])
        expectEqual(s.browser.activeTab, 1)
        expect(s.browser.canGoBack && s.browser.isFavorite && !s.browser.isHome)
        expectEqual(s.music?.title, "Song")
        expectEqual(s.music?.elapsed, 12.5)
        expectEqual(s.timer.state, .running)
        expectEqual(s.timer.progress, 0.25)
        expect(s.note.isEditing)
        expectEqual(s.captions.lines, ["Hello"])
        expectEqual(s.youtube.page, .player)
        expectEqual(s.youtube.tab, .search)
        expectEqual(s.youtube.results.first?.meta, "1K views")
        expectEqual(s.photos.count, 248)
        expectEqual(s.photos.selected, 7)
        expect(s.photos.viewing)
        expectEqual(s.photos.caption, "12 OCTOBER 2026")
        expect(s.prompter.isRunning)
        expectEqual(s.prompter.step, 4)
        // Applied, it replaces the apps but keeps this phone's own sky.
        var mine = HudSnapshot.blank
        mine.skyView.fov = 33
        let shown = s.applied(to: mine)
        expectEqual(shown.browser.title, "Wikipedia")
        expectEqual(shown.skyView.fov, 33)
        expectEqual(shown.photos.count, 248)
    }

    // Against a real Android phone, when asked: HUD_REMOTE_LINK="thehud://connect?…" swift run hudtests
    if let link = ProcessInfo.processInfo.environment["HUD_REMOTE_LINK"] {
        test("live: pairs with the Android phone and gets its state") {
            guard let pairing = RemotePairing(link: link) else { return expect(false, "bad link") }
            MainActor.assumeIsolated {
                let remote = RemoteLink()
                var state: RemoteState?
                remote.onState = { state = $0 }
                remote.connect(pairing)
                let deadline = Date().addingTimeInterval(8)
                while state == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                expect(remote.isConnected, "connected: \(remote.status)")
                expect(state != nil, "a state arrived")
                expect(!(state?.scenes.isEmpty ?? true), "scenes in it")
                // A wrong key is refused, and stays refused rather than retrying.
                var wrong = pairing
                wrong.key = Data(repeating: 1, count: 32)
                remote.connect(wrong)
                let until = Date().addingTimeInterval(5)
                while remote.status != .refused, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                expectEqual(remote.status, .refused)
                remote.disconnect()
            }
        }
    }
}
