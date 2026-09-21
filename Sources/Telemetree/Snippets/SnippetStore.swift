import Foundation

/// Persists snippets and snippet folders as JSON in Application Support.
/// Structurally identical to QueryStore — same reasoning applies: no
/// Keychain needed, SQL text isn't a secret.
@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    @Published private(set) var folders: [SnippetFolder] = []

    private let storeURL: URL
    private var pendingSave: DispatchWorkItem?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Telemetree", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("snippets.json")
        load()
    }

    func snippet(id: UUID) -> Snippet? {
        snippets.first { $0.id == id }
    }

    @discardableResult
    func createSnippet(name: String = "New Snippet", folderID: UUID? = nil) -> Snippet {
        let maxOrder = snippets.filter { $0.folderID == folderID }.map(\.sortOrder).max() ?? -1
        let snippet = Snippet(name: name, folderID: folderID, sortOrder: maxOrder + 1)
        snippets.append(snippet)
        saveSoon()
        return snippet
    }

    func rename(_ snippetID: UUID, to name: String) {
        guard let index = snippets.firstIndex(where: { $0.id == snippetID }) else { return }
        snippets[index].name = name
        saveSoon()
    }

    func updateSQL(_ snippetID: UUID, sql: String) {
        guard let index = snippets.firstIndex(where: { $0.id == snippetID }) else { return }
        snippets[index].sql = sql
        saveSoon()
    }

    @discardableResult
    func duplicate(_ snippetID: UUID) -> Snippet? {
        guard let original = snippet(id: snippetID) else { return nil }
        let copy = createSnippet(name: original.name + " copy", folderID: original.folderID)
        updateSQL(copy.id, sql: original.sql)
        return snippet(id: copy.id)
    }

    func delete(_ snippetID: UUID) {
        snippets.removeAll { $0.id == snippetID }
        saveSoon()
    }

    func move(_ snippetID: UUID, toFolder folderID: UUID?) {
        guard let index = snippets.firstIndex(where: { $0.id == snippetID }) else { return }
        snippets[index].folderID = folderID
        saveSoon()
    }

    @discardableResult
    func createFolder(name: String = "New Folder", parentID: UUID? = nil) -> SnippetFolder {
        let maxOrder = folders.filter { $0.parentID == parentID }.map(\.sortOrder).max() ?? -1
        let folder = SnippetFolder(name: name, parentID: parentID, sortOrder: maxOrder + 1)
        folders.append(folder)
        saveSoon()
        return folder
    }

    func renameFolder(_ folderID: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].name = name
        saveSoon()
    }

    func deleteFolder(_ folderID: UUID) {
        for index in snippets.indices where snippets[index].folderID == folderID {
            snippets[index].folderID = nil
        }
        for index in folders.indices where folders[index].parentID == folderID {
            folders[index].parentID = nil
        }
        folders.removeAll { $0.id == folderID }
        saveSoon()
    }

    private func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private struct Snapshot: Codable {
        var snippets: [Snippet]
        var folders: [SnippetFolder]
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snippets = snapshot.snippets
        folders = snapshot.folders
    }

    private func save() {
        let snapshot = Snapshot(snippets: snippets, folders: folders)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
