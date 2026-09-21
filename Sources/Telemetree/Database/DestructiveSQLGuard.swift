import Foundation

/// Flags SQL that should require the user to re-authenticate (system
/// password or Touch ID) before it runs. Deliberately simple — a keyword
/// check, not a parser: DELETE/DROP/TRUNCATE/UPDATE always confirm.
///
/// UPDATE used to only confirm when it had no WHERE clause (an unscoped
/// UPDATE is as dangerous as a DELETE, so that much still applies) — but a
/// *scoped* UPDATE still overwrites real data, just like DELETE does even
/// with a WHERE clause, so exempting it was inconsistent. Always confirm.
enum DestructiveSQLGuard {
    private static let alwaysConfirm: Set<String> = ["delete", "drop", "truncate", "update"]

    static func isDestructive(_ sql: String) -> Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstWord = trimmed.split(whereSeparator: { $0.isWhitespace }).first?.lowercased() else {
            return false
        }
        return alwaysConfirm.contains(firstWord)
    }
}
