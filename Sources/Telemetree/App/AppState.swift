import Foundation
import Combine
import LocalAuthentication

@MainActor
final class AppState: ObservableObject {
    let connectionManager = ConnectionManager()
    let queryStore = QueryStore()
    let snippetStore = SnippetStore()
    let themeStore = ThemeStore()
    let syntaxThemeStore = SyntaxThemeStore()
    let fontPreferences = FontPreferencesStore()
    let historyStore = QueryHistoryStore()

    /// One-shot "insert this SQL at the caret" events for the active
    /// editor — not @Published state, since it's a fire-and-forget
    /// request, not something with a persistent value to hold.
    let insertRequests = PassthroughSubject<String, Never>()

    @Published private(set) var openDocumentIDs: [UUID] = []
    @Published private(set) var activeDocumentID: UUID?

    private var openStates: [UUID: OpenDocumentState] = [:]
    private let workspaceURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Telemetree", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        workspaceURL = dir.appendingPathComponent("workspace.json")
        loadWorkspace()

        if queryStore.documents.isEmpty {
            newDocument()
        }
    }

    // MARK: - Open document access

    func state(for documentID: UUID) -> OpenDocumentState? {
        if let cached = openStates[documentID] { return cached }
        guard let document = queryStore.document(id: documentID) else { return nil }
        let state = OpenDocumentState(document: document)
        openStates[documentID] = state
        return state
    }

    var activeState: OpenDocumentState? {
        activeDocumentID.flatMap { state(for: $0) }
    }

    var activeDocument: QueryDocument? {
        activeDocumentID.flatMap { queryStore.document(id: $0) }
    }

    var selectedProfile: ConnectionProfile? {
        guard let id = activeState?.connectionProfileID else { return nil }
        return connectionManager.profiles.first { $0.id == id }
    }

    // MARK: - Workspace actions

    @discardableResult
    func newDocument(connectionProfileID: UUID? = nil, folderID: UUID? = nil) -> QueryDocument {
        let document = queryStore.createDocument(connectionProfileID: connectionProfileID, folderID: folderID)
        openDocument(document.id)
        return document
    }

    func openDocument(_ documentID: UUID) {
        guard state(for: documentID) != nil else { return }
        if !openDocumentIDs.contains(documentID) {
            openDocumentIDs.append(documentID)
        }
        activeDocumentID = documentID
        saveWorkspace()
    }

    func activate(_ documentID: UUID) {
        guard openDocumentIDs.contains(documentID) else { return }
        activeDocumentID = documentID
        saveWorkspace()
    }

    func closeDocument(_ documentID: UUID) {
        guard let index = openDocumentIDs.firstIndex(of: documentID) else { return }
        openDocumentIDs.remove(at: index)
        openStates[documentID] = nil
        if activeDocumentID == documentID {
            let fallbackIndex = min(index, openDocumentIDs.count - 1)
            activeDocumentID = fallbackIndex >= 0 ? openDocumentIDs[fallbackIndex] : nil
        }
        saveWorkspace()
    }

    /// Used when the schema browser wants to drop a SELECT into the editor:
    /// targets the active document, opening a scratch one if nothing is open.
    func runQuery(_ sql: String, connectionProfileID: UUID) {
        let documentID = activeDocumentID ?? newDocument(connectionProfileID: connectionProfileID).id
        guard let state = state(for: documentID) else { return }
        state.connectionProfileID = connectionProfileID
        state.sql = sql
        queryStore.setConnection(documentID, connectionProfileID: connectionProfileID)
        queryStore.updateSQL(documentID, sql: sql)
        if !openDocumentIDs.contains(documentID) {
            openDocument(documentID)
        } else {
            activate(documentID)
        }
        executeCurrentSQL()
    }

    func setActiveConnection(_ connectionProfileID: UUID) {
        let documentID = activeDocumentID ?? newDocument(connectionProfileID: connectionProfileID).id
        guard let state = state(for: documentID) else { return }
        state.connectionProfileID = connectionProfileID
        queryStore.setConnection(documentID, connectionProfileID: connectionProfileID)
    }

    func insertSnippetIntoActiveEditor(_ sql: String) {
        insertRequests.send(sql)
    }

    /// Reopens a history entry as a new query document.
    func reopenHistoryEntry(_ entry: QueryHistoryEntry) {
        let document = newDocument(connectionProfileID: entry.connectionProfileID)
        guard let state = state(for: document.id) else { return }
        state.sql = entry.sql
        queryStore.updateSQL(document.id, sql: entry.sql)
    }

    func updateActiveSQL(_ sql: String) {
        guard let documentID = activeDocumentID, let state = state(for: documentID) else { return }
        state.sql = sql
        queryStore.updateSQL(documentID, sql: sql)
    }

    /// Page size for auto-paginated SELECTs — see `executeCurrentSQL`.
    static let resultPageSize = 500

    /// `overrideSQL`, when given, is what actually runs instead of the
    /// whole document — the SQL editor passes the statement under the
    /// caret (or the real selection, if any) so Run never fires an
    /// unrelated statement sitting elsewhere in a multi-statement buffer.
    func executeCurrentSQL(_ overrideSQL: String? = nil) {
        guard let state = activeState else { return }
        let sql = (overrideSQL ?? state.sql).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }
        guard let profileID = state.connectionProfileID,
              let connection = connectionManager.connection(for: profileID) else {
            state.errorMessage = "No active connection. Connect to a database first."
            return
        }
        let connectionName = connectionManager.profiles.first { $0.id == profileID }?.name ?? "Unknown"

        // A plain, un-LIMITed SELECT gets paged automatically so a huge
        // table doesn't get pulled entirely into memory in one shot;
        // anything else (DML, or a SELECT that already has its own LIMIT)
        // runs exactly as written.
        let paginate = Self.isUnlimitedSelect(sql)
        state.paginationBaseSQL = paginate ? sql : nil
        state.paginationOffset = 0
        state.hasMorePages = false
        let runSQL = paginate ? "\(sql) LIMIT \(Self.resultPageSize)" : sql

        Task {
            if DestructiveSQLGuard.isDestructive(sql) {
                guard await Self.confirmDestructiveQuery() else {
                    state.errorMessage = "Cancelled — authentication is required to run this query."
                    return
                }
            }

            state.isExecuting = true
            state.errorMessage = nil
            do {
                let result = try await connection.execute(sql: runSQL)
                state.queryResult = result
                state.hasMorePages = paginate && result.rows.count == Self.resultPageSize
                historyStore.record(sql: sql, connectionProfileID: profileID, connectionName: connectionName, succeeded: true, errorMessage: nil)
            } catch {
                state.errorMessage = error.localizedDescription
                historyStore.record(sql: sql, connectionProfileID: profileID, connectionName: connectionName, succeeded: false, errorMessage: error.localizedDescription)
            }
            state.isExecuting = false
        }
    }

    /// Fetches the next page for the currently displayed result, appending
    /// its rows to what's already shown.
    func loadMoreRows() {
        guard let state = activeState,
              let baseSQL = state.paginationBaseSQL,
              state.hasMorePages, !state.isExecuting,
              let profileID = state.connectionProfileID,
              let connection = connectionManager.connection(for: profileID) else { return }
        let nextOffset = state.paginationOffset + Self.resultPageSize

        Task {
            state.isExecuting = true
            do {
                let page = try await connection.execute(sql: "\(baseSQL) LIMIT \(Self.resultPageSize) OFFSET \(nextOffset)")
                state.queryResult = QueryResult(
                    columns: state.queryResult.columns,
                    rows: state.queryResult.rows + page.rows,
                    affectedRows: state.queryResult.affectedRows
                )
                state.paginationOffset = nextOffset
                state.hasMorePages = page.rows.count == Self.resultPageSize
            } catch {
                state.errorMessage = error.localizedDescription
            }
            state.isExecuting = false
        }
    }

    // ponytail: keyword check, not a parser — same tradeoff as
    // DestructiveSQLGuard. A `LIMIT` inside a subquery/CTE falsely
    // suppresses auto-paging of the outer SELECT; acceptable since the
    // fallback is just "no paging," not a wrong result.
    private static func isUnlimitedSelect(_ sql: String) -> Bool {
        sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("SELECT")
            && sql.range(of: "limit", options: .caseInsensitive) == nil
    }

    /// Requires the system password or Touch ID before a destructive
    /// query runs. Fails closed: if device-owner authentication can't be
    /// evaluated at all (no policy available), the query is blocked.
    private static func confirmDestructiveQuery() async -> Bool {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "run this query"
            )
        } catch {
            return false
        }
    }

    // MARK: - Workspace persistence

    private struct WorkspaceSnapshot: Codable {
        var openDocumentIDs: [UUID]
        var activeDocumentID: UUID?
    }

    private func loadWorkspace() {
        guard let data = try? Data(contentsOf: workspaceURL),
              let snapshot = try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data) else { return }
        let validIDs = snapshot.openDocumentIDs.filter { queryStore.document(id: $0) != nil }
        openDocumentIDs = validIDs
        activeDocumentID = snapshot.activeDocumentID.flatMap { validIDs.contains($0) ? $0 : validIDs.first }
    }

    private func saveWorkspace() {
        let snapshot = WorkspaceSnapshot(openDocumentIDs: openDocumentIDs, activeDocumentID: activeDocumentID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: workspaceURL, options: .atomic)
    }
}
