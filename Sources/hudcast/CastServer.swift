import Foundation
import Network
import HudCore

/// Advertises HudCast on the local network and talks to one phone at a time. A new phone
/// replaces the old one: the newest connection is the one being looked at.
final class CastServer: @unchecked Sendable {
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onCommand: ((DesktopCommand) -> Void)?
    var onState: ((String) -> Void)?

    private let queue = DispatchQueue(label: "hudcast.server")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var parser = DesktopWire.Parser()
    /// Frames handed to the network and not yet sent. Past a few, the capture skips frames
    /// rather than queueing a backlog that would put the picture seconds behind.
    private var inFlight = 0
    private let lock = NSLock()

    var isBackedUp: Bool { lock.withLock { inFlight > 3 } }

    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcp.noDelay = true
            }
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac",
                                                  type: DesktopWire.service)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.onState?("Waiting for iPhone")
                case let .failed(error): self?.onState?("Network error: \(error)")
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            queue.async { self.listener = listener }
        } catch {
            onState?("Could not listen: \(error)")
        }
    }

    /// Stops advertising and lets the phone go. `start()` opens up again.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            if let connection = self.connection {
                self.connection = nil
                connection.cancel()
                self.onDisconnect?()
            }
        }
    }

    private func accept(_ new: NWConnection) {
        connection?.cancel()
        connection = new
        parser = DesktopWire.Parser()
        lock.withLock { inFlight = 0 }
        new.stateUpdateHandler = { [weak self, weak new] state in
            guard let self, let new, new === self.connection else { return }
            switch state {
            case .ready: self.onConnect?()
            case .failed, .cancelled:
                self.connection = nil
                self.onDisconnect?()
            default: break
            }
        }
        new.start(queue: queue)
        receive(on: new)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, complete, error in
            guard let self, connection === self.connection else { return }
            if let data, !data.isEmpty {
                for (kind, payload) in self.parser.feed(data) where kind == .command {
                    if let command = try? JSONDecoder().decode(DesktopCommand.self, from: payload) {
                        self.onCommand?(command)
                    }
                }
            }
            if complete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection)
        }
    }

    func send<T: Encodable>(_ kind: DesktopWire.Kind, json value: T) {
        send(DesktopWire.pack(kind, json: value), counted: false)
    }

    func sendFrame(keyframe: Bool, avcc: Data, sps: Data?, pps: Data?) {
        var data = Data()
        if let sps, let pps {
            data.append(DesktopWire.pack(.format, DesktopWire.formatPayload(sps: sps, pps: pps)))
        }
        data.append(DesktopWire.pack(.frame, DesktopWire.framePayload(keyframe: keyframe, avcc: avcc)))
        send(data, counted: true)
    }

    private func send(_ data: Data, counted: Bool) {
        queue.async { [weak self] in
            guard let self, let connection = self.connection else { return }
            if counted { self.lock.withLock { self.inFlight += 1 } }
            connection.send(content: data, completion: .contentProcessed { [weak self] _ in
                if counted { self?.lock.withLock { self?.inFlight -= 1 } }
            })
        }
    }
}
