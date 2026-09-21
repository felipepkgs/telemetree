import Foundation

/// Flags SQL that should require the user to re-authenticate (system
/// password or Touch ID) before it runs. Deliberately simple — a keyword
/// check, not a parser: DELETE/DROP/TRUNCATE always confirm; UPDATE only
/// confirms when it has no WHERE clause (an unscoped UPDATE is just as
/// dangerous as a DELETE).
enum DestructiveSQLGuard {
    private static let alwaysConfirm: Set<String> = ["delete", "drop", "truncate"]
    private static let whereRegex = try! NSRegularExpression(pattern: #"\bwhere\b"#, options: .caseInsensitive)

    static func isDestructive(_ sql: String) -> Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstWord = trimmed.split(whereSeparator: { $0.isWhitespace }).first?.lowercased() else {
            return false
        }
        if alwaysConfirm.contains(firstWord) {
            return true
        }
        guard firstWord == "update" else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return whereRegex.firstMatch(in: trimmed, range: range) == nil
    }
}
