import Foundation

/// Saved caption sessions: one plain text file each, in the app's Documents folder, so they
/// show in the Files app as well as in Settings.
public enum CaptionsLog {
    public struct Session: Identifiable, Hashable, Sendable {
        public var url: URL
        public var date: Date
        public var lines: Int
        public var preview: String
        public var id: URL { url }
    }

    public static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Captions", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    /// Starts a file for a session.
    public static func begin(at date: Date, in folder: URL = directory) -> URL {
        let name = "Captions " + formatter("yyyy-MM-dd HH.mm.ss").string(from: date) + ".txt"
        let url = folder.appendingPathComponent(name)
        let header = "Captions \u{2014} " + DateFormatter.localizedString(from: date, dateStyle: .full,
                                                                     timeStyle: .short) + "\n\n"
        try? header.data(using: .utf8)?.write(to: url)
        return url
    }

    /// Adds a finished sentence with the time it was said.
    public static func append(_ text: String, at date: Date, to url: URL) {
        let line = "[" + formatter("HH:mm:ss").string(from: date) + "] " + text + "\n"
        guard let data = line.data(using: .utf8), let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    public static func sessions(in folder: URL = directory) -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "txt" }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let spoken = text.split(separator: "\n").filter { $0.hasPrefix("[") }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let preview = spoken.prefix(2).map { line in
                line.split(separator: "]", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            }.joined(separator: " ")
            return Session(url: url, date: date, lines: spoken.count, preview: preview)
        }
        .sorted { $0.date > $1.date }
    }

    public static func delete(_ session: Session) {
        try? FileManager.default.removeItem(at: session.url)
    }
}
