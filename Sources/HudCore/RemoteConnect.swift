import Foundation
import Network
import CryptoKit

// Remote Connect: this app working the glasses of the Android phone that drives them.
//
// The Android phone listens on the local network and shows a QR code: its id, its address, and a
// secret key. This end connects, answers the phone's random challenge with an HMAC of it under
// the key, and from then on sends what its own screen did (actions, touchpad gestures, typing)
// and gets the Android phone's state back to draw. One line of JSON per message, over TCP. The
// phone is also on Bonjour as `_thehud-remote._tcp`, named by its id, so it is found again when its
// address changes.

/// What the QR code says, kept once scanned.
public struct RemotePairing: Codable, Equatable, Sendable {
    public var id: String
    public var key: Data
    public var host: String
    public var port: UInt16

    public static let scheme = "thehud"
    public static let service = "_thehud-remote._tcp"

    public init(id: String, key: Data, host: String, port: UInt16) {
        self.id = id
        self.key = key
        self.host = host
        self.port = port
    }

    /// `thehud://connect?id=…&k=…&h=…&p=…`, the key in unpadded base64url.
    public init?(link: String) {
        guard let components = URLComponents(string: link), components.scheme == Self.scheme,
              components.host == "connect" else { return nil }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                               uniquingKeysWith: { first, _ in first })
        guard let id = items["id"], !id.isEmpty, let k = items["k"], let key = Data(base64URL: k),
              key.count >= 16 else { return nil }
        self.init(id: id, key: key, host: items["h"] ?? "", port: UInt16(items["p"] ?? "") ?? 47825)
    }

    /// The Bonjour name the phone advertises.
    public var serviceName: String { "TheHud-\(id)" }

    /// The answer to the phone's challenge.
    public func proof(for nonce: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: nonce, using: SymmetricKey(data: key)))
    }
}

extension Data {
    init?(base64URL string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}

/// The Android phone, as this phone's screen draws it.
public struct RemoteState: Sendable {
    public var arrangement = HudArrangement()
    public var solo: HudPanelKind?
    public var clearView = false
    public var scene = 0
    public var scenes: [String] = []
    public var glassesConnected = false
    /// Where its keyboard types, by name (`address`, `page`, `note`, `mapSearch`, `mac`, `youtubeSearch`).
    public var keyboard: String?
    public var draft = ""
    public var browser = HudSnapshot.Browser(url: "", title: "", tabs: ["New Tab"], activeTab: 0, isHome: true)
    public var music: HudSnapshot.NowPlaying?
    public var timer = HudSnapshot.TimerReading()
    public var note = HudSnapshot.Note()
    public var captions = HudSnapshot.Captions()
    public var youtube = HudSnapshot.YouTube()
    public var photos = HudSnapshot.Photos()
    /// Running and how fast; where the words are is the Android phone's business.
    public var prompter = HudSnapshot.Prompter()

    public init() {}

    /// This phone's snapshot with the Android phone's apps in it. The sky stays this phone's:
    /// it is the same sky.
    public func applied(to snapshot: HudSnapshot) -> HudSnapshot {
        var s = snapshot
        s.browser = browser
        s.music = music
        s.timer = timer
        s.note = note
        s.captions = captions
        s.youtube = youtube
        s.photos = photos
        s.prompter = prompter
        return s
    }
}

/// The messages both ways, as plain JSON objects.
public enum RemoteWire {
    // ------------------------------------------------------------------ to the Android phone

    /// What a button on this phone means on the Android phone. Nil for what stays on this phone
    /// (settings, the pad, arranging) or has no counterpart there.
    public static func message(for action: PhoneAction) -> [String: Any]? {
        func act(_ a: String, _ extra: [String: Any] = [:]) -> [String: Any] {
            ["t": "action", "a": a].merging(extra) { $1 }
        }
        switch action {
        case .back: return act("back")
        case .forward: return act("forward")
        case .reload: return act("reload")
        case .home: return act("home")
        case .favorite: return act("favorite")
        case .address: return act("address")
        case .keyboard: return act("keyboard")
        case .newTab: return act("newTab")
        case .clearView: return act("clearView")
        case let .selectTab(i): return act("selectTab", ["i": i])
        case let .closeTab(i): return act("closeTab", ["i": i])
        case let .tapPanel(kind): return act("tapPanel", ["kind": kind.rawValue])
        case let .solo(kind): return act("solo", ["kind": kind.rawValue])
        case let .centre(kind): return act("centre", ["kind": kind.rawValue])
        case let .place(kind, spot): return act("place", ["kind": kind.rawValue, "spot": spotName(spot)])
        case let .scene(i): return act("scene", ["i": i])
        case let .resetScene(i): return act("resetScene", ["i": i])
        case let .layout(edge): return act("layout", ["edge": edge?.rawValue ?? NSNull()])
        case let .selectWindow(i): return act("macWindow", ["i": i ?? -1])
        case let .music(control):
            switch control {
            case .previous: return act("music", ["c": "previous"])
            case .playPause: return act("music", ["c": "playPause"])
            case .next: return act("music", ["c": "next"])
            }
        case let .timer(t):
            switch t {
            case .toggle: return act("timer", ["c": "toggle"])
            case .reset: return act("timer", ["c": "reset"])
            case let .set(minutes): return act("timer", ["c": "set", "m": minutes])
            case let .add(minutes): return act("timer", ["c": "add", "m": minutes])
            }
        case let .note(n):
            switch n {
            case .write: return act("note", ["c": "write"])
            case .clear: return act("note", ["c": "clear"])
            case let .scroll(by): return act("note", ["c": "scroll", "by": by.isFinite ? Double(by) : -1e9])
            }
        case .captionsToggle: return act("captions")
        case let .sky(s):
            switch s {
            case let .look(pan, tilt): return act("sky", ["c": "look", "pan": pan, "tilt": tilt])
            case let .zoom(f): return act("sky", ["c": "zoom", "f": f])
            case .recentre: return act("sky", ["c": "recentre"])
            case let .toggle(layer): return act("sky", ["c": "toggle", "layer": layer.rawValue])
            case let .select(id): return act("sky", ["c": "select", "id": id ?? ""])
            }
        case let .youtube(y):
            switch y {
            case .togglePlay: return act("youtube", ["c": "togglePlay"])
            case .next: return act("youtube", ["c": "next"])
            case .skipAd: return act("youtube", ["c": "skipAd"])
            case let .seek(by): return act("youtube", ["c": "seek", "by": by])
            case .search: return act("youtube", ["c": "search"])
            case let .play(v): return act("youtube", ["c": "play", "video": video(v)])
            case let .playQueued(i): return act("youtube", ["c": "playQueued", "i": i])
            case let .enqueue(v): return act("youtube", ["c": "enqueue", "video": video(v)])
            case let .dequeue(i): return act("youtube", ["c": "dequeue", "i": i])
            case let .page(p): return act("youtube", ["c": "page", "page": p == .player ? "player" : "browse"])
            }
        case let .prompter(p):
            switch p {
            case .toggle: return act("prompter", ["c": "toggle"])
            case .faster: return act("prompter", ["c": "faster"])
            case .slower: return act("prompter", ["c": "slower"])
            case .restart: return act("prompter", ["c": "restart"])
            }
        case let .photos(p):
            switch p {
            case let .step(by): return act("photos", ["c": "step", "by": by])
            case .open: return act("photos", ["c": "open"])
            }
        case .settings, .editGlasses, .showWindows, .pad, .remote, .captionsSessions, .captionsLanguage,
             .remoteConnect:
            return nil
        }
    }

    public static func spotName(_ spot: HudSpot) -> String {
        switch spot {
        case let .slot(side, i): "\(side.rawValue):\(i)"
        case let .row(i): "row:\(i)"
        case .middle: "middle"
        case .off: "off"
        }
    }

    private static func video(_ v: YouTubeVideo) -> [String: Any] {
        ["id": v.id, "title": v.title, "channel": v.channel, "duration": v.duration, "meta": v.meta]
    }

    public static func message(for event: GestureEvent) -> [String: Any] {
        func g(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
            ["t": "gesture", "g": name].merging(extra) { $1 }
        }
        switch event {
        case let .move(dx, dy, dragging): return g("move", ["dx": dx, "dy": dy, "drag": dragging])
        case let .click(button, down): return g("click", ["button": button == .left ? 1 : 2, "down": down])
        case let .scroll(v, h): return g("scroll", ["v": v, "h": h])
        case let .scrollFling(vx, vy): return g("fling", ["vx": Double(vx), "vy": Double(vy)])
        case let .pinch(scale): return g("pinch", ["s": Double(scale)])
        case .tapClick: return g("tap")
        case .rightClick: return g("right")
        case .doubleTapDragStart: return g("dragStart")
        case .dragEnd: return g("dragEnd")
        }
    }

    /// The remote's middle: the cursor back to the middle of the glasses.
    public static func centreCursor() -> [String: Any] { ["t": "gesture", "g": "centre"] }

    // ------------------------------------------------------------------ from the Android phone

    public static func state(from o: [String: Any]) -> RemoteState {
        var s = RemoteState()
        if let a = o["arrangement"], let data = try? JSONSerialization.data(withJSONObject: a),
           let arrangement = try? JSONDecoder().decode(HudArrangement.self, from: data) {
            s.arrangement = arrangement
        }
        s.solo = (o["solo"] as? String).flatMap(HudPanelKind.init(rawValue:))
        s.clearView = o["clearView"] as? Bool ?? false
        s.scene = o["scene"] as? Int ?? 0
        s.scenes = o["scenes"] as? [String] ?? []
        s.glassesConnected = o["glasses"] as? Bool ?? false
        s.keyboard = o["keyboard"] as? String
        s.draft = o["draft"] as? String ?? ""
        if let b = o["browser"] as? [String: Any] {
            s.browser = HudSnapshot.Browser(url: b["url"] as? String ?? "", title: b["title"] as? String ?? "",
                                            tabs: b["tabs"] as? [String] ?? [], activeTab: b["activeTab"] as? Int ?? 0,
                                            canGoBack: b["canGoBack"] as? Bool ?? false,
                                            canGoForward: b["canGoForward"] as? Bool ?? false,
                                            isHome: b["isHome"] as? Bool ?? true,
                                            isFavorite: b["isFavorite"] as? Bool ?? false)
        }
        if let m = o["music"] as? [String: Any] {
            s.music = HudSnapshot.NowPlaying(title: m["title"] as? String ?? "", artist: m["artist"] as? String ?? "",
                                             album: m["album"] as? String ?? "", isPlaying: m["isPlaying"] as? Bool ?? false,
                                             elapsed: number(m["elapsed"]), duration: number(m["duration"]))
        }
        if let t = o["timer"] as? [String: Any] {
            s.timer.text = t["text"] as? String ?? ""
            s.timer.progress = (t["progress"] as? NSNumber)?.doubleValue
            s.timer.state = switch t["state"] as? String {
            case "running": .running
            case "paused": .paused
            case "done": .done
            default: .idle
            }
            s.timer.isStopwatch = t["isStopwatch"] as? Bool ?? false
        }
        if let n = o["note"] as? [String: Any] {
            s.note.text = n["text"] as? String ?? ""
            s.note.isEditing = n["isEditing"] as? Bool ?? false
        }
        if let c = o["captions"] as? [String: Any] {
            s.captions.isListening = c["isListening"] as? Bool ?? false
            s.captions.lines = c["lines"] as? [String] ?? []
            s.captions.partial = c["partial"] as? String ?? ""
            s.captions.status = c["status"] as? String ?? ""
            s.captions.elapsed = c["elapsed"] as? String ?? ""
        }
        if let y = o["youtube"] as? [String: Any] {
            var v = HudSnapshot.YouTube()
            v.hasVideo = y["hasVideo"] as? Bool ?? false
            v.videoId = y["videoId"] as? String ?? ""
            v.title = y["title"] as? String ?? ""
            v.channel = y["channel"] as? String ?? ""
            v.isPlaying = y["isPlaying"] as? Bool ?? false
            v.isLive = y["isLive"] as? Bool ?? false
            v.elapsed = number(y["elapsed"])
            v.duration = number(y["duration"])
            v.isAd = y["isAd"] as? Bool ?? false
            v.canSkipAd = y["canSkipAd"] as? Bool ?? false
            v.notice = y["notice"] as? String ?? ""
            v.page = y["page"] as? String == "player" ? .player : .browse
            v.tab = (y["tab"] as? String).flatMap(HudSnapshot.YouTube.Tab.init(rawValue:)) ?? .home
            v.showsSubscriptions = y["showsSubscriptions"] as? Bool ?? false
            v.query = y["query"] as? String ?? ""
            v.isEditingQuery = y["isEditingQuery"] as? Bool ?? false
            v.home = videos(y["home"])
            v.subscriptions = videos(y["subscriptions"])
            v.results = videos(y["results"])
            v.upNext = videos(y["upNext"])
            v.queue = videos(y["queue"])
            s.youtube = v
        }
        if let p = o["photos"] as? [String: Any] {
            s.photos.hasAccess = p["hasAccess"] as? Bool ?? true
            s.photos.count = p["count"] as? Int ?? 0
            s.photos.current = p["current"] as? Int ?? 0
            s.photos.selected = p["selected"] as? Int ?? 0
            s.photos.scrollRow = p["scrollRow"] as? Int ?? 0
            s.photos.viewing = p["viewing"] as? Bool ?? false
            s.photos.caption = p["caption"] as? String ?? ""
        }
        if let p = o["prompter"] as? [String: Any] {
            s.prompter.isRunning = p["isRunning"] as? Bool ?? false
            s.prompter.speed = (p["speed"] as? NSNumber)?.doubleValue ?? 60
        }
        return s
    }

    private static func number(_ any: Any?) -> Double { (any as? NSNumber)?.doubleValue ?? 0 }

    private static func videos(_ any: Any?) -> [YouTubeVideo] {
        (any as? [[String: Any]] ?? []).map {
            YouTubeVideo(id: $0["id"] as? String ?? "", title: $0["title"] as? String ?? "",
                         channel: $0["channel"] as? String ?? "", duration: $0["duration"] as? String ?? "",
                         meta: $0["meta"] as? String ?? "")
        }
    }

    /// One message as a line.
    public static func line(_ object: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        data.append(0x0A)
        return data
    }
}

/// The connection to the Android phone: kept up while paired, found again by Bonjour when its
/// address changes, retried when it drops.
@MainActor
public final class RemoteLink {
    public enum Status: Equatable, Sendable {
        /// Not paired, or paired and switched off.
        case off
        case connecting
        /// In, with the phone's name.
        case connected(String)
        /// Refused: the code was replaced on the Android phone.
        case refused
    }

    public private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatus?(status) } }
    }
    public var onStatus: ((Status) -> Void)?
    public var onState: ((RemoteState) -> Void)?
    /// Host mode: the Android phone asks for a keyframe (its picture starts or restarts).
    public var onKeyframe: (() -> Void)?
    public private(set) var pairing: RemotePairing?
    /// Host mode, set before connecting: this phone runs the apps and sends its glasses' picture;
    /// the Android phone only shows it. Otherwise this phone is the Android phone's remote.
    public var hosting = false
    /// Bytes given to the connection and not yet sent: Host mode drops frames past a backlog.
    public private(set) var unsentBytes = 0

    private let queue = DispatchQueue(label: "thehud.remote")
    private var connection: NWConnection?
    private var buffer = Data()
    private var authed = false
    private var attempt = 0
    private var retry: Task<Void, Never>?

    public init() {}

    public var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    /// Connects, and keeps connecting, until `disconnect`.
    public func connect(_ pairing: RemotePairing) {
        disconnect()
        self.pairing = pairing
        attempt = 0
        open()
    }

    public func disconnect() {
        retry?.cancel()
        retry = nil
        pairing = nil
        close()
        status = .off
    }

    public func send(_ object: [String: Any]) {
        guard authed, let connection, let line = RemoteWire.line(object) else { return }
        connection.send(content: line, completion: .idempotent)
    }

    /// Host mode: framed picture data, as it is.
    public func sendPacket(_ data: Data) {
        guard authed, hosting, let connection else { return }
        unsentBytes += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] _ in
            Task { @MainActor in
                guard let self, let connection, connection === self.connection else { return }
                self.unsentBytes = max(self.unsentBytes - data.count, 0)
            }
        })
    }

    private static var parameters: NWParameters {
        let parameters = NWParameters.tcp
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 5
            tcp.connectionTimeout = 4
        }
        return parameters
    }

    private func open() {
        guard let pairing else { return }
        status = .connecting
        // The address in the code first, then the name on Bonjour, in turn: the address is
        // quickest, the name survives the phone getting a new one.
        let endpoint: NWEndpoint
        if attempt % 2 == 0, !pairing.host.isEmpty, let port = NWEndpoint.Port(rawValue: pairing.port) {
            endpoint = .hostPort(host: NWEndpoint.Host(pairing.host), port: port)
        } else {
            endpoint = .service(name: pairing.serviceName, type: RemotePairing.service, domain: "local.", interface: nil)
        }
        attempt += 1
        let connection = NWConnection(to: endpoint, using: Self.parameters)
        self.connection = connection
        buffer = Data()
        authed = false
        unsentBytes = 0
        connection.stateUpdateHandler = { [weak self, weak connection] update in
            Task { @MainActor in
                guard let self, let connection, connection === self.connection else { return }
                switch update {
                case .failed, .cancelled: self.dropped()
                case .waiting: self.dropped()
                default: break
                }
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func close() {
        let connection = self.connection
        self.connection = nil
        authed = false
        connection?.cancel()
    }

    private func dropped(after delay: Double? = nil) {
        // Shut on the proof: the code was replaced on the Android phone, and only scanning
        // the new one gets back in.
        let refused = awaitingWelcome
        awaitingWelcome = false
        close()
        if refused, pairing != nil {
            retry?.cancel()
            status = .refused
            return
        }
        guard pairing != nil, status != .refused else { return }
        status = .connecting
        retry?.cancel()
        let wait = delay ?? min(1.0 + Double(attempt) * 0.5, 5)
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    private nonisolated func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, connection === self.connection else { return }
                if let data, !data.isEmpty { self.feed(data) }
                if complete || error != nil {
                    self.dropped()
                } else {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func feed(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            handle(object)
        }
    }

    private func handle(_ o: [String: Any]) {
        switch o["t"] as? String {
        case "hello":
            guard let pairing, let nonce = (o["nonce"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let connection else { return }
            pendingName = o["name"] as? String ?? "Android"
            let auth: [String: Any] = ["t": "auth", "mac": pairing.proof(for: nonce).base64EncodedString(),
                                       "name": Self.deviceName, "mode": hosting ? "host" : "remote"]
            if let line = RemoteWire.line(auth) { connection.send(content: line, completion: .idempotent) }
            awaitingWelcome = true
        case "welcome":
            awaitingWelcome = false
            authed = true
            attempt = 0
            status = .connected(pendingName)
        case "state":
            guard authed, !hosting else { return }
            onState?(RemoteWire.state(from: o))
        case "keyframe":
            guard authed, hosting else { return }
            onKeyframe?()
        default:
            break
        }
    }

    private var pendingName = ""
    private var awaitingWelcome = false

    /// What the Android phone shows as connected.
    public static var deviceName: String {
        #if os(iOS)
        return "iPhone"
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}
