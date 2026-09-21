import Foundation
import MySQLNIO

/// Turns a raw driver error into something a person can act on. MySQLNIO's
/// own `MySQLError.server(_:)` carries the real MySQL error code, which is
/// far more reliable to branch on than string-matching a message — that
/// part's a real lookup. The connection-level cases (refused/timeout/
/// unreachable) only have a localized description to go on, since NIO
/// doesn't give a structured error for them here — that part's a
/// best-effort keyword match, not exhaustive.
enum FriendlyError {
    static func message(for error: Error) -> String {
        if let mysqlError = error as? MySQLError {
            return message(for: mysqlError)
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

    private static func message(forDescription description: String) -> String {
        let lowered = description.lowercased()
        if lowered.contains("connection refused") {
            return "Couldn't connect — the server refused the connection. Check the host and port, and that MySQL is running there."
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
        let description = String(describing: error).lowercased()
        return description.contains("closed") || description.contains("channel is not active") || description.contains("connection reset")
    }
}
