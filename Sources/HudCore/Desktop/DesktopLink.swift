import Foundation
import Network
import AVFoundation

/// The phone's end of the desktop stream: finds HudCast on the local network, keeps one
/// connection to it, shows what it sends, and sends back the cursor and keys.
///
/// The picture goes straight into a display layer, which decodes the H.264 in hardware; the
/// view that shows it only hosts the layer.
@MainActor
public final class DesktopLink {
    public private(set) var state = HudSnapshot.Desktop() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((HudSnapshot.Desktop) -> Void)?

    public let displayLayer: AVSampleBufferDisplayLayer = {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        return layer
    }()

    private let queue = DispatchQueue(label: "thehud.desktop")
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var endpoints: [NWEndpoint] = []
    private var parser = DesktopWire.Parser()
    private var depacketizer = DesktopDepacketizer()
    /// After a flush the decoder needs a keyframe before anything else makes sense.
    private var waitingForKeyframe = true
    /// The panel is on. Off, a dropped connection stays dropped.
    private var active = false

    public init() {}

    /// Starts looking for a Mac. Safe to call again; it only starts once.
    public func start() {
        guard browser == nil else { return }
        active = true
        let browser = NWBrowser(for: .bonjour(type: DesktopWire.service, domain: nil),
                                using: Self.parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.map(\.endpoint)
            Task { @MainActor in
                self?.endpoints = endpoints
                self?.connectIfIdle()
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.state.status = "CANNOT SEARCH THE NETWORK" }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// The panel went away: let go of the Mac, so it stops capturing and encoding.
    public func stop() {
        guard active else { return }
        active = false
        browser?.cancel()
        browser = nil
        endpoints = []
        let connection = self.connection
        self.connection = nil
        connection?.cancel()
        clear()
        state.status = "LOOKING FOR YOUR MAC"
    }

    private func clear() {
        state.connected = false
        state.hasPicture = false
        state.source = nil
        state.windows = []
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    private static var parameters: NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        return parameters
    }

    private func connectIfIdle() {
        guard active, connection == nil, let endpoint = endpoints.first else {
            if active, connection == nil { state.status = "LOOKING FOR YOUR MAC" }
            return
        }
        var name = ""
        if case let .service(serviceName, _, _, _) = endpoint { name = serviceName }
        state.status = "CONNECTING TO \(name.uppercased())"
        state.host = name

        let connection = NWConnection(to: endpoint, using: Self.parameters)
        self.connection = connection
        parser = DesktopWire.Parser()
        waitingForKeyframe = true
        connection.stateUpdateHandler = { [weak self, weak connection] update in
            Task { @MainActor in
                guard let self, let connection, connection === self.connection else { return }
                switch update {
                case .ready:
                    self.state.connected = true
                    self.state.status = "WAITING FOR \(self.state.host.uppercased())"
                case .failed, .cancelled:
                    self.dropped()
                default: break
                }
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func dropped() {
        connection?.cancel()
        connection = nil
        clear()
        // Try again shortly: HudCast restarting, or the Mac waking, should come back by itself.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            self.connectIfIdle()
        }
    }

    private nonisolated func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) {
            [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, connection === self.connection else { return }
                if let data, !data.isEmpty {
                    for (kind, payload) in self.parser.feed(data) { self.handle(kind, payload) }
                }
                if complete || error != nil {
                    self.dropped()
                } else {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func handle(_ kind: DesktopWire.Kind, _ payload: Data) {
        switch kind {
        case .windows:
            state.windows = (try? JSONDecoder().decode([DesktopWindow].self, from: payload)) ?? []
        case .source:
            if let source = try? JSONDecoder().decode(DesktopSource.self, from: payload) {
                state.source = source
                state.host = source.host
            }
        case .format:
            if let sets = DesktopWire.parseFormat(payload) {
                depacketizer.setFormat(sps: sets.sps, pps: sets.pps)
            }
        case .frame:
            guard let frame = DesktopWire.parseFrame(payload) else { return }
            let renderer = displayLayer.sampleBufferRenderer
            if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
                renderer.flush()
                waitingForKeyframe = true
            }
            if waitingForKeyframe {
                guard frame.keyframe else { return }
                waitingForKeyframe = false
            }
            if let sample = depacketizer.sampleBuffer(avcc: frame.avcc) {
                renderer.enqueue(sample)
                if !state.hasPicture { state.hasPicture = true }
            }
        case .command:
            break
        }
    }

    public func send(_ command: DesktopCommand) {
        guard let connection, state.connected,
              let data = try? JSONEncoder().encode(command) else { return }
        connection.send(content: DesktopWire.pack(.command, data), completion: .idempotent)
    }
}
