import Foundation

/// Persists query documents and folders as JSON in Application Support.
/// Mirrors ConnectionManager's persistence approach — no Keychain needed
/// here since SQL text isn't a secret.
@MainActor
final class QueryStore: ObservableObject {
    @Published private(set) var documents: [QueryDocument] = []
    @Published private(set) var temporaryDocuments: [QueryDocument] = []
    @Published private(set) var folders: [QueryFolder] = []

    nonisolated static let untitledQueryName = "Untitled Query"

    private let storeURL: URL
    private var pendingSave: DispatchWorkItem?

    init(storeURL: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Telemetree", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storeURL = storeURL ?? dir.appendingPathComponent("queries.json")
        load()
    }

    func document(id: UUID) -> QueryDocument? {
        documents.first { $0.id == id } ?? temporaryDocuments.first { $0.id == id }
    }

    func isTemporaryDocument(_ documentID: UUID) -> Bool {
        temporaryDocuments.contains { $0.id == documentID }
    }

    @discardableResult
    func createTemporaryDocument(name: String, connectionProfileID: UUID? = nil) -> QueryDocument {
        let document = QueryDocument(name: name, connectionProfileID: connectionProfileID)
        temporaryDocuments.append(document)
        return document
    }

    func saveTemporaryDocument(_ documentID: UUID, name: String, folderID: UUID?) {
        guard let index = temporaryDocuments.firstIndex(where: { $0.id == documentID }) else { return }
        var document = temporaryDocuments.remove(at: index)
        document.name = name
        document.folderID = folderID
        document.sortOrder = (documents.filter { $0.folderID == folderID }.map(\.sortOrder).max() ?? -1) + 1
        document.updatedAt = Date()
        documents.append(document)
        saveSoon()
    }

    @discardableResult
    func createDocument(name: String = QueryStore.untitledQueryName, connectionProfileID: UUID? = nil, folderID: UUID? = nil) -> QueryDocument {
        let maxOrder = documents.filter { $0.folderID == folderID }.map(\.sortOrder).max() ?? -1
        let document = QueryDocument(name: name, connectionProfileID: connectionProfileID, folderID: folderID, sortOrder: maxOrder + 1)
        documents.append(document)
        saveSoon()
        return document
    }

    func rename(_ documentID: UUID, to name: String) {
        if let index = documents.firstIndex(where: { $0.id == documentID }) {
            documents[index].name = name
            saveSoon()
        } else if let index = temporaryDocuments.firstIndex(where: { $0.id == documentID }) {
            temporaryDocuments[index].name = name
        }
    }

    func updateSQL(_ documentID: UUID, sql: String) {
        if let index = documents.firstIndex(where: { $0.id == documentID }) {
            documents[index].sql = sql
            documents[index].updatedAt = Date()
            saveSoon()
        } else if let index = temporaryDocuments.firstIndex(where: { $0.id == documentID }) {
            temporaryDocuments[index].sql = sql
            temporaryDocuments[index].updatedAt = Date()
        }
    }

    func setConnection(_ documentID: UUID, connectionProfileID: UUID?) {
        if let index = documents.firstIndex(where: { $0.id == documentID }) {
            documents[index].connectionProfileID = connectionProfileID
            saveSoon()
        } else if let index = temporaryDocuments.firstIndex(where: { $0.id == documentID }) {
            temporaryDocuments[index].connectionProfileID = connectionProfileID
        }
    }

    func setLabelColor(_ documentID: UUID, color: LabelColor?) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[index].labelColor = color
        saveSoon()
    }

    func setFolderLabelColor(_ folderID: UUID, color: LabelColor?) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].labelColor = color
        saveSoon()
    }

    @discardableResult
    func duplicate(_ documentID: UUID) -> QueryDocument? {
        guard let original = document(id: documentID) else { return nil }
        let copy = createDocument(
            name: original.name + " copy",
            connectionProfileID: original.connectionProfileID,
            folderID: original.folderID
        )
        updateSQL(copy.id, sql: original.sql)
        return document(id: copy.id)
    }

    func delete(_ documentID: UUID) {
        let previousCount = documents.count
        documents.removeAll { $0.id == documentID }
        temporaryDocuments.removeAll { $0.id == documentID }
        if documents.count != previousCount { saveSoon() }
    }

    func move(_ documentID: UUID, toFolder folderID: UUID?) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[index].folderID = folderID
        saveSoon()
    }

    @discardableResult
    func createFolder(name: String = "New Folder", parentID: UUID? = nil) -> QueryFolder {
        let maxOrder = folders.filter { $0.parentID == parentID }.map(\.sortOrder).max() ?? -1
        let folder = QueryFolder(name: name, parentID: parentID, sortOrder: maxOrder + 1)
        folders.append(folder)
        saveSoon()
        return folder
    }

    func renameFolder(_ folderID: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].name = name
        saveSoon()
    }

    /// Deletes a folder without cascading: contents are reparented to root.
    func deleteFolder(_ folderID: UUID) {
        for index in documents.indices where documents[index].folderID == folderID {
            documents[index].folderID = nil
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
        var documents: [QueryDocument]
        var folders: [QueryFolder]
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        documents = snapshot.documents
        folders = snapshot.folders
    }

    private func save() {
        let snapshot = Snapshot(documents: documents, folders: folders)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
