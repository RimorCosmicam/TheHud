import Foundation

/// The Mac-to-phone link, on the wire.
///
/// One TCP connection over the local network, found by Bonjour. Every message is a kind byte, a
/// four-byte big-endian length, and that many bytes. Video goes Mac to phone as H.264 in AVCC
/// form, which is what VideoToolbox produces and what CoreMedia consumes, so neither end has to
/// rewrite it. Everything else is small JSON.
public enum DesktopWire {
    /// What HudCast advertises and the phone browses for.
    public static let service = "_thehud._tcp"

    public enum Kind: UInt8, Sendable {
        /// Mac to phone: the windows that can be streamed, `[DesktopWindow]`.
        case windows = 1
        /// Mac to phone: H.264 parameter sets, sent with every keyframe.
        case format = 2
        /// Mac to phone: one encoded frame.
        case frame = 3
        /// Mac to phone: what is being streamed, `DesktopSource`.
        case source = 4
        /// Phone to Mac: input and requests, `DesktopCommand`.
        case command = 16
    }

    public static let headerSize = 5
    /// Nothing legitimate is this large; a length past it means the stream is out of step.
    public static let maxPayload = 32 << 20

    public static func pack(_ kind: Kind, _ payload: Data) -> Data {
        var data = Data(capacity: headerSize + payload.count)
        data.append(kind.rawValue)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    public static func pack<T: Encodable>(_ kind: Kind, json value: T) -> Data {
        pack(kind, (try? JSONEncoder().encode(value)) ?? Data())
    }

    /// The header's kind and length.
    public static func header(_ bytes: Data) -> (kind: Kind?, length: Int)? {
        guard bytes.count >= headerSize else { return nil }
        let start = bytes.startIndex
        let length = bytes[(start + 1)..<(start + 5)].reduce(0) { $0 << 8 | Int($1) }
        guard length <= maxPayload else { return nil }
        return (Kind(rawValue: bytes[start]), length)
    }

    /// Reassembles messages from a byte stream that arrives in arbitrary pieces.
    public struct Parser: Sendable {
        private var buffer = Data()
        public init() {}

        public mutating func feed(_ bytes: Data) -> [(Kind, Data)] {
            buffer.append(bytes)
            var messages: [(Kind, Data)] = []
            while let (kind, length) = DesktopWire.header(buffer),
                  buffer.count >= DesktopWire.headerSize + length {
                let start = buffer.startIndex + DesktopWire.headerSize
                let payload = buffer.subdata(in: start..<(start + length))
                buffer.removeSubrange(buffer.startIndex..<(start + length))
                if let kind { messages.append((kind, payload)) }
            }
            return messages
        }
    }

    // ------------------------------------------------------------------ video payloads

    /// SPS and PPS, each with a two-byte length.
    public static func formatPayload(sps: Data, pps: Data) -> Data {
        var data = Data()
        for set in [sps, pps] {
            data.append(UInt8(set.count >> 8))
            data.append(UInt8(set.count & 0xFF))
            data.append(set)
        }
        return data
    }

    public static func parseFormat(_ data: Data) -> (sps: Data, pps: Data)? {
        var sets: [Data] = []
        var index = data.startIndex
        while sets.count < 2, index + 2 <= data.endIndex {
            let length = Int(data[index]) << 8 | Int(data[index + 1])
            index += 2
            guard index + length <= data.endIndex else { return nil }
            sets.append(data.subdata(in: index..<(index + length)))
            index += length
        }
        return sets.count == 2 ? (sets[0], sets[1]) : nil
    }

    /// One flag byte (bit 0: keyframe), then the frame's AVCC NAL units.
    public static func framePayload(keyframe: Bool, avcc: Data) -> Data {
        var data = Data([keyframe ? 1 : 0])
        data.append(avcc)
        return data
    }

    public static func parseFrame(_ data: Data) -> (keyframe: Bool, avcc: Data)? {
        guard let flags = data.first else { return nil }
        return (flags & 1 == 1, data.dropFirst())
    }
}

/// A window on the Mac that can be streamed on its own.
public struct DesktopWindow: Codable, Sendable, Hashable {
    public var id: UInt32
    public var app: String
    public var title: String

    public init(id: UInt32, app: String, title: String) {
        self.id = id
        self.app = app
        self.title = title
    }

    /// "Safari — Apple", or just the app when the window has no title.
    public var label: String { title.isEmpty || title == app ? app : "\(app) \u{2014} \(title)" }
}

/// What the Mac is streaming right now.
public struct DesktopSource: Codable, Sendable, Hashable {
    /// Nil for the whole display.
    public var window: UInt32?
    public var width: Int
    public var height: Int
    /// The Mac's name, for the glasses to say what they are showing.
    public var host: String

    public init(window: UInt32?, width: Int, height: Int, host: String) {
        self.window = window
        self.width = width
        self.height = height
        self.host = host
    }
}

/// From the phone. Positions are 0...1 across the streamed picture, so the phone never needs
/// to know the Mac's screen size or where a window is on it.
public enum DesktopCommand: Codable, Sendable, Equatable {
    case move(x: Double, y: Double)
    /// `button` 0 is left, 1 is right.
    case click(x: Double, y: Double, button: Int)
    /// Press, drag with further `move`s, release: windows dragged, text selected.
    case press(x: Double, y: Double)
    case release(x: Double, y: Double)
    /// Pixels, positive up and left, as a scroll wheel reports them.
    case scroll(x: Double, y: Double, dx: Double, dy: Double)
    case text(String)
    /// "delete", "return", "tab", "escape", "left", "right", "up", "down".
    case key(String)
    /// Stream one window, or the whole display with nil.
    case select(window: UInt32?)
}
