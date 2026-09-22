import Foundation

/// A single value returned in a query result row.
enum QueryValue: Equatable {
    case null
    case text(String)

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var displayString: String {
        switch self {
        case .null: return "NULL"
        case .text(let value): return value
        }
    }
}

struct QueryResult: Equatable {
    let columns: [String]
    let rows: [[QueryValue]]
    let affectedRows: Int?

    static let empty = QueryResult(columns: [], rows: [], affectedRows: nil)
}

struct DatabaseTable: Identifiable, Hashable {
    var id: String { name }
    let name: String
}

enum DatabaseError: LocalizedError {
    case connectionFailed(String)
    case queryFailed(String)
    /// The underlying socket is gone (as opposed to a normal query-level
    /// failure where the connection itself is still fine) — lets
    /// AppState flip the sidebar's connected state to match reality.
    case connectionLost(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message): return "Connection failed: \(message)"
        case .queryFailed(let message): return message
        case .connectionLost(let message): return message
        }
    }
}

/// An open connection to a database server, capable of running SQL and
/// browsing basic schema metadata. Implementations are engine-specific
/// (MySQL today, others later) and hidden behind this protocol so the UI
/// never depends on a concrete driver.
protocol DatabaseConnection: AnyObject {
    func execute(sql: String) async throws -> QueryResult
    func listDatabases() async throws -> [String]
    func listTables(inDatabase database: String) async throws -> [DatabaseTable]
    func listColumns(table: String, inDatabase database: String) async throws -> [String]
    func close() async
}

/// Opens connections for a given engine from a `ConnectionProfile`.
protocol DatabaseDriver {
    func connect(profile: ConnectionProfile, password: String) async throws -> any DatabaseConnection
}
