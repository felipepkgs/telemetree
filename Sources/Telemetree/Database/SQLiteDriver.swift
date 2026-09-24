import Foundation
import CSQLite

/// SQLite implementation of the database abstraction — the system's own
/// libsqlite3 via a raw C module map (Package.swift's CSQLite target),
/// not an external Swift package: sqlite3 already ships with macOS, so
/// pulling in GRDB or SQLite.swift for this would just be a heavier way
/// to do what the platform already provides.
///
/// A `sqlite3*` handle isn't safe to touch from more than one thread at
/// once — every operation is funneled through a single serial
/// DispatchQueue per connection (mirroring the single-EventLoopGroup
/// pattern the MySQL/Postgres drivers already use for the same reason).
final class SQLiteDriver: DatabaseDriver {
    func connect(profile: ConnectionProfile, password: String) async throws -> any DatabaseConnection {
        let path = profile.filePath
        guard !path.isEmpty else {
            throw DatabaseError.connectionFailed("No database file selected.")
        }
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open \(path)"
            if let handle { sqlite3_close(handle) }
            throw DatabaseError.connectionFailed(message)
        }
        return SQLiteDatabaseConnection(handle: handle, fileName: (path as NSString).lastPathComponent)
    }
}

// @unchecked: every access to `handle` is funneled through `queue`
// (a private serial queue never exposed outside this file), so it's
// never actually touched from two threads at once — the compiler just
// can't verify that itself from an OpaquePointer capture.
final class SQLiteDatabaseConnection: DatabaseConnection, @unchecked Sendable {
    private let handle: OpaquePointer
    private let fileName: String
    private let queue = DispatchQueue(label: "com.telemetree.app.sqlite")

    init(handle: OpaquePointer, fileName: String) {
        self.handle = handle
        self.fileName = fileName
    }

    func execute(sql: String) async throws -> QueryResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try Self.runSync(sql: sql, handle: self.handle) })
            }
        }
    }

    private static func runSync(sql: String, handle: OpaquePointer) throws -> QueryResult {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        var columns: [String] = []
        for i in 0..<columnCount {
            columns.append(String(cString: sqlite3_column_name(statement, i)))
        }

        var rows: [[QueryValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                var row: [QueryValue] = []
                for i in 0..<columnCount {
                    row.append(value(statement: statement, column: i))
                }
                rows.append(row)
            } else if step == SQLITE_DONE {
                break
            } else {
                throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }

        if columns.isEmpty {
            // DML (INSERT/UPDATE/DELETE) has no result columns at all —
            // sqlite3_changes() is the real affected-row count, the SQLite
            // analogue of MySQL's OK_Packet.affectedRows.
            return QueryResult(columns: [], rows: [], affectedRows: Int(sqlite3_changes(handle)))
        }
        return QueryResult(columns: columns, rows: rows, affectedRows: rows.count)
    }

    /// Unlike MySQL/Postgres, SQLite is dynamically (not statically)
    /// typed per-value — sqlite3_column_text() itself already converts
    /// any INTEGER/REAL/TEXT value to its display string, so there's no
    /// per-column-type branching needed the way the other two drivers
    /// require; only NULL and BLOB need explicit handling.
    private static func value(statement: OpaquePointer, column: Int32) -> QueryValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_NULL:
            return .null
        case SQLITE_BLOB:
            let length = sqlite3_column_bytes(statement, column)
            return .text("<blob, \(length) bytes>")
        default:
            guard let text = sqlite3_column_text(statement, column) else { return .null }
            return .text(String(cString: text))
        }
    }

    func listDatabases() async throws -> [String] {
        // SQLite has no multi-database-per-server concept the way
        // MySQL/Postgres do — one file is the whole "database". A single
        // synthetic entry keeps the sidebar's connection -> database ->
        // tables tree structurally the same across all three engines.
        [fileName]
    }

    func listTables(inDatabase database: String) async throws -> [DatabaseTable] {
        let result = try await execute(sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        return result.rows.compactMap { $0.first.map { DatabaseTable(name: $0.displayString) } }
    }

    func listColumns(table: String, inDatabase database: String) async throws -> [String] {
        let result = try await execute(sql: "PRAGMA table_info(\(quotedIdentifier(table)))")
        // PRAGMA table_info's 2nd column ("name") is the column name;
        // the 1st ("cid") is just its ordinal index.
        return result.rows.compactMap { $0.count > 1 ? $0[1].displayString : nil }
    }

    /// PRAGMA doesn't accept bound parameters for its target name, so the
    /// identifier is inlined directly — quoted with doubled internal
    /// quotes (SQLite's standard identifier-escaping rule) rather than
    /// interpolated raw.
    private func quotedIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    func activeSessions() async throws -> QueryResult {
        // No server/session concept for a single local file — the UI
        // doesn't offer this feature for SQLite at all, but the protocol
        // conformance still needs a body.
        .empty
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                sqlite3_close(self.handle)
                continuation.resume()
            }
        }
    }
}
