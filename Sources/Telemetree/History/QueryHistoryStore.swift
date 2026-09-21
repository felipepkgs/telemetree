import Foundation

/// Append-only log of executed queries, persisted like the other stores.
/// Capped at maxEntries so it can't grow unbounded over months of use.
@MainActor
final class QueryHistoryStore: ObservableObject {
    @Published private(set) var entries: [QueryHistoryEntry] = []

    private let storeURL: URL
    private let maxEntries = 500
    private var pendingSave: DispatchWorkItem?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Telemetree", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("history.json")
        load()
    }

    func record(sql: String, connectionProfileID: UUID?, connectionName: String, succeeded: Bool, errorMessage: String?) {
        let entry = QueryHistoryEntry(
            sql: sql,
            connectionProfileID: connectionProfileID,
            connectionName: connectionName,
            succeeded: succeeded,
            errorMessage: errorMessage
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        saveSoon()
    }

    func clear() {
        entries = []
        saveSoon()
    }

    private func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([QueryHistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
