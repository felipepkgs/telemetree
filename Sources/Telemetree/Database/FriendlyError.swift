import Foundation
import MySQLNIO
import PostgresNIO

/// Turns a raw driver error into something a person can act on. MySQLNIO's
/// own `MySQLError.server(_:)` and PostgresNIO's `PSQLError.serverInfo`
/// carry the real server error code, which is far more reliable to branch
/// on than string-matching a message — that part's a real lookup for both
/// engines. The connection-level cases (refused/timeout/unreachable) only
/// have a localized description to go on, since neither driver gives a
/// structured error for them here — that part's a best-effort keyword
/// match, not exhaustive, but it's engine-agnostic so it also covers
/// SQLite's plain-string `sqlite3_errmsg` errors, which don't have a
/// structured code to branch on at all.
enum FriendlyError {
    static func message(for error: Error) -> String {
        if let mysqlError = error as? MySQLError {
            return message(for: mysqlError)
        }
        if let postgresError = error as? PSQLError {
            return message(for: postgresError)
        }
        return message(forDescription: error.localizedDescription)
    }

    private static func message(for error: MySQLError) -> String {
        switch error {
        case .server(let packet):
            switch packet.errorCode.rawValue {
            case 1045: return "Access denied — check the username and password."
            case 1044, 1049: return "Database not found — check the database name."
            case 1146: return "Table doesn't exist — check the table name."
            case 1054: return "Unknown column — check the column name in your query."
            case 1213: return "Deadlock detected — try running the query again."
            case 1205: return "Query timed out waiting on a lock — try again, or check for a long-running transaction."
            default: return packet.errorMessage
            }
        case .invalidSyntax(let message):
            return "SQL syntax error: \(message)"
        case .duplicateEntry(let message):
            return "Duplicate entry: \(message)"
        case .closed:
            return "The connection was closed — reconnect and try again."
        case .secureConnectionRequired:
            return "This server requires a secure connection. Enable \u{201C}Use SSL\u{201D} for this connection."
        default:
            return error.message
        }
    }

    /// SQLSTATE codes per the Postgres manual (Appendix A) — the same
    /// lookup MySQL's numeric error codes get above, just a different
    /// code space.
    private static func message(for error: PSQLError) -> String {
        if let sqlState = error.serverInfo?[.sqlState] {
            switch sqlState {
            case "28P01", "28000": return "Access denied — check the username and password."
            case "3D000": return "Database not found — check the database name."
            case "42P01": return "Table doesn't exist — check the table name."
            case "42703": return "Unknown column — check the column name in your query."
            case "40P01": return "Deadlock detected — try running the query again."
            case "55P03": return "Query timed out waiting on a lock — try again, or check for a long-running transaction."
            case "23505": return "Duplicate entry: \(error.serverInfo?[.message] ?? sqlState)"
            case "42601": return "SQL syntax error: \(error.serverInfo?[.message] ?? sqlState)"
            default: break
            }
        }
        if let message = error.serverInfo?[.message] {
            return message
        }
        return message(forDescription: String(describing: error))
    }

    private static func message(forDescription description: String) -> String {
        let lowered = description.lowercased()
        if lowered.contains("connection refused") {
            return "Couldn't connect — the server refused the connection. Check the host and port, and that the database server is running there."
        }
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return "Connection timed out — check the host and port, and your network connection."
        }
        if lowered.contains("no route to host") || lowered.contains("network is unreachable") {
            return "Couldn't reach the host — check the host address and your network connection."
        }
        return description
    }

    /// Whether the error means the underlying socket is gone — as opposed
    /// to a normal query-level failure (bad SQL, permissions, etc.) where
    /// the connection itself is still fine. Used to flip the sidebar's
    /// connected/not-connected state to match reality instead of leaving
    /// it showing "connected" against a dead connection.
    static func isConnectionLost(_ error: Error) -> Bool {
        if case MySQLError.closed = error { return true }
        if let postgresError = error as? PSQLError,
           postgresError.code == .clientClosedConnection || postgresError.code == .serverClosedConnection {
            return true
        }
        let description = String(describing: error).lowercased()
        return description.contains("closed") || description.contains("channel is not active") || description.contains("connection reset")
    }
}
