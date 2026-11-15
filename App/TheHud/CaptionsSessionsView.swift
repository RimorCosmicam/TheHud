import SwiftUI
import HudCore

/// Every saved captions session, newest first: search them, read one, share it, delete it.
/// The same files are in the Files app under On My iPhone › TheHud › Captions.
struct CaptionsSessionsView: View {
    @State private var sessions: [CaptionsLog.Session] = []
    @State private var query = ""

    private var shown: [CaptionsLog.Session] {
        guard !query.isEmpty else { return sessions }
        return sessions.filter { session in
            (try? String(contentsOf: session.url, encoding: .utf8))?
                .localizedCaseInsensitiveContains(query) ?? false
        }
    }

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("Turn on Captions on the glasses and what is said is saved here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { session in
                NavigationLink {
                    CaptionsSessionView(session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text(session.preview.isEmpty ? "Nothing said" : session.preview)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text("\(session.lines) lines").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { CaptionsLog.delete(shown[index]) }
                sessions = CaptionsLog.sessions()
            }
        }
        .searchable(text: $query, prompt: "Search what was said")
        .navigationTitle("Saved captions")
        .onAppear { sessions = CaptionsLog.sessions() }
    }
}

struct CaptionsSessionView: View {
    let session: CaptionsLog.Session
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: session.url)
            }
        }
        .onAppear { text = (try? String(contentsOf: session.url, encoding: .utf8)) ?? "" }
    }
}
