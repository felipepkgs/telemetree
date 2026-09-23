import Foundation

enum DatabaseEngine: String, Codable, CaseIterable, Identifiable {
    case mysql
    case postgres
    case sqlite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mysql: return "MySQL"
        case .postgres: return "PostgreSQL"
        case .sqlite: return "SQLite"
        }
    }

    var defaultPort: Int {
        switch self {
        case .mysql: return 3306
        case .postgres: return 5432
        case .sqlite: return 0
        }
    }

    /// SQLite connects to a single local file, not a host/port/username
    /// server — the New Connection UI and driver both branch on this
    /// instead of repeating the engine == .sqlite check everywhere.
    var connectsToFile: Bool { self == .sqlite }

    /// Quotes a table/column identifier the way this engine actually
    /// accepts. Postgres only understands ANSI double quotes for
    /// identifiers — backticks are a hard syntax error there, not just a
    /// style difference (confirmed live: "syntax error at or near \"`\""
    /// from a query built with MySQL-style backtick quoting). MySQL
    /// defaults to backtick-only (ANSI_QUOTES is off unless explicitly
    /// enabled, so a double-quoted identifier there is read as a string
    /// literal instead, not a syntax error but silently the wrong thing).
    /// SQLite accepts both leniently; backtick is used for it too since
    /// that's the common ground with MySQL for any shared code path.
    func quoteIdentifier(_ name: String) -> String {
        switch self {
        case .postgres:
            return "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        case .mysql, .sqlite:
            return "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
        }
    }
}
