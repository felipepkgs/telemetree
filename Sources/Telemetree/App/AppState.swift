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

    /// Clicking a database in the sidebar sets it as that connection's
    /// default schema (a real `USE`, server-side — session state on the
    /// shared connection, so it applies no matter which document/tab is
    /// active) so an unqualified `SELECT * FROM orders` resolves without
    /// having to write `` `database`.`orders` `` every time.
    func selectDatabase(_ database: String, profileID: UUID) {
        setActiveConnection(profileID)
        guard let profile = connectionManager.profiles.first(where: { $0.id == profileID }) else { return }
        Task {
            if !connectionManager.connectedIDs.contains(profileID) {
                await connectionManager.connect(profile)
            }
            guard let connection = connectionManager.connection(for: profileID) else { return }
            // Only MySQL has a session-level USE — Postgres has no
            // equivalent at all (a connection is bound to one database
            // for its lifetime; "switching" means a new connection, not
            // a statement) and SQLite has nothing to switch between
            // (one file is the whole "database"). Trying USE on either
            // would just be a guaranteed syntax error.
            guard profile.engine == .mysql else { return }
            guard (try? await connection.execute(sql: "USE \(profile.engine.quoteIdentifier(database))")) != nil else { return }
            connectionManager.setCurrentDatabase(database, for: profileID)
        }
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
    static let resultPageSize = 100

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
        let paginationBase = Self.stripTrailingSemicolon(sql)
        state.paginationBaseSQL = paginate ? paginationBase : nil
        state.currentPage = 0
        state.totalRowCount = nil
        state.editableTable = EditableResultDetector.singleSourceTable(in: sql)
        let runSQL = paginate ? "\(paginationBase) LIMIT \(Self.resultPageSize)" : sql

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
                historyStore.record(sql: sql, connectionProfileID: profileID, connectionName: connectionName, succeeded: true, errorMessage: nil)
                if paginate {
                    fetchTotalRowCount(baseSQL: paginationBase, connection: connection, state: state)
                }
            } catch {
                state.errorMessage = error.localizedDescription
                if case DatabaseError.connectionLost = error {
                    connectionManager.markDisconnected(profileID)
                }
                historyStore.record(sql: sql, connectionProfileID: profileID, connectionName: connectionName, succeeded: false, errorMessage: error.localizedDescription)
            }
            state.isExecuting = false
        }
    }

    /// Runs separately from the page fetch, and doesn't block showing the
    /// first page — COUNT(*) over a big table can be slow, so the page
    /// controls just show a total/page count once this resolves instead
    /// of making the user wait for it up front.
    private func fetchTotalRowCount(baseSQL: String, connection: any DatabaseConnection, state: OpenDocumentState) {
        Task {
            guard let result = try? await connection.execute(sql: "SELECT COUNT(*) FROM (\(baseSQL)) AS telemetree_count"),
                  let raw = result.rows.first?.first?.displayString,
                  let count = Int(raw) else { return }
            state.totalRowCount = count
        }
    }

    /// Fetches and displays one page of the current paginated result —
    /// replaces the grid's rows rather than appending to them, since
    /// paging (not "load more") is now the model.
    func goToPage(_ page: Int) {
        guard let state = activeState,
              let baseSQL = state.paginationBaseSQL,
              page >= 0, !state.isExecuting,
              let profileID = state.connectionProfileID,
              let connection = connectionManager.connection(for: profileID) else { return }
        let offset = page * Self.resultPageSize

        Task {
            state.isExecuting = true
            do {
                let result = try await connection.execute(sql: "\(baseSQL) LIMIT \(Self.resultPageSize) OFFSET \(offset)")
                state.queryResult = result
                state.currentPage = page
            } catch {
                state.errorMessage = error.localizedDescription
            }
            state.isExecuting = false
        }
    }

    /// Commits one inline cell edit from the results grid as a real
    /// UPDATE, scoped to `whereColumns`/`whereValues` (the row's primary
    /// key, captured by the caller before the edit — see
    /// ResultsGridViewController). Deliberately NOT routed through
    /// executeCurrentSQL: that replaces the grid's displayed result with
    /// whatever the statement returns, which for an UPDATE would blank
    /// the currently-shown page with the UPDATE's own (empty) result
    /// instead of refreshing it.
    func updateCell(
        table: String,
        setColumn: String,
        oldValue: QueryValue,
        newValue: QueryValue,
        whereColumns: [String],
        whereValues: [QueryValue]
    ) {
        guard let state = activeState,
              let profileID = state.connectionProfileID,
              let connection = connectionManager.connection(for: profileID),
              let profile = connectionManager.profiles.first(where: { $0.id == profileID }),
              !whereColumns.isEmpty else { return }
        let connectionName = profile.name
        let engine = profile.engine

        let setClause = "\(engine.quoteIdentifier(setColumn)) = \(Self.sqlLiteral(newValue))"
        // Primary key columns are never actually NULL in a valid schema,
        // so a plain `=` (not `IS NULL`) is a safe simplification here.
        let whereClause = zip(whereColumns, whereValues)
            .map { "\(engine.quoteIdentifier($0)) = \(Self.sqlLiteral($1))" }
            .joined(separator: " AND ")
        let sql = "UPDATE \(engine.quoteIdentifier(table)) SET \(setClause) WHERE \(whereClause)"

        Task {
            // Same gate executeCurrentSQL uses for a typed UPDATE — a
            // generated single-row edit can't bypass Touch ID just
            // because it didn't come from the text editor.
            if DestructiveSQLGuard.isDestructive(sql) {
                // Shows the actual old → new value right in the system
                // auth prompt — the lightweight version of "diff before
                // commit": you see exactly what's about to change before
                // authenticating, without a separate diff UI to build.
                let reason = "change \(setColumn) from \u{201C}\(oldValue.displayString)\u{201D} to \u{201C}\(newValue.displayString)\u{201D}"
                guard await Self.confirmDestructiveQuery(reason: reason) else {
                    state.errorMessage = "Cancelled — authentication is required to run this query."
                    return
                }
            }
            do {
                _ = try await connection.execute(sql: sql)
                historyStore.record(sql: sql, connectionProfileID: profileID, connectionName: connectionName, succeeded: true, errorMessage: nil)
                // Refresh whatever's currently on screen instead of
                // leaving it showing pre-edit data.
                if state.paginationBaseSQL != nil {
                    goToPage(state.currentPage)
                } else {
                    executeCurrentSQL(state.sql)
                }
            } catch {
                state.errorMessage = error.localizedDescription
                if case DatabaseError.connectionLost = error {
                    connectionManager.markDisconnected(profileID)
                }
                historyStore.record(sql: sql, connectionProfileID: profileID, connectionName: connectionName, succeeded: false, errorMessage: error.localizedDescription)
            }
        }
    }

    private static func sqlLiteral(_ value: QueryValue) -> String {
        switch value {
        case .null: return "NULL"
        case .text(let string): return "'" + string.replacingOccurrences(of: "'", with: "''") + "'"
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

    /// A trailing `;` (near-universal SQL style) left in place before
    /// appending `LIMIT ...`/`LIMIT ... OFFSET ...` produces invalid
    /// syntax like `SELECT * FROM x; LIMIT 500` — found via a real MySQL
    /// syntax error while testing pagination against a live connection,
    /// not by inspection.
    private static func stripTrailingSemicolon(_ sql: String) -> String {
        var trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(";") {
            trimmed.removeLast()
        }
        return trimmed
    }

    /// Requires the system password or Touch ID before a destructive
    /// query runs. Fails closed: if device-owner authentication can't be
    /// evaluated at all (no policy available), the query is blocked.
    private static func confirmDestructiveQuery(reason: String = "run this query") async -> Bool {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
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
