import Foundation

/// Detects whether a SELECT's result can safely support inline cell
/// editing in the results grid — only when there's exactly one
/// unambiguous source table. Deliberately simple, a keyword check not a
/// parser (same tradeoff as DestructiveSQLGuard/SQLStatementLocator
/// elsewhere in this app): a query with a JOIN, or any other query shape
/// this can't confidently read as "one table," is left non-editable
/// rather than guessed at.
enum EditableResultDetector {
    private static let fromRegex = try! NSRegularExpression(
        pattern: #"\bFROM\s+(?:[`"]?[A-Za-z_][A-Za-z0-9_]*[`"]?\.)?[`"]?([A-Za-z_][A-Za-z0-9_]*)[`"]?"#,
        options: .caseInsensitive
    )
    private static let joinRegex = try! NSRegularExpression(pattern: #"\bJOIN\b"#, options: .caseInsensitive)

    /// The single source table name, or nil if the query isn't a plain
    /// single-table SELECT.
    static func singleSourceTable(in sql: String) -> String? {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("SELECT") else { return nil }
        let nsSQL = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsSQL.length)

        guard joinRegex.firstMatch(in: trimmed, range: fullRange) == nil else { return nil }

        let matches = fromRegex.matches(in: trimmed, range: fullRange)
        guard matches.count == 1, let match = matches.first, match.numberOfRanges > 1 else { return nil }
        return nsSQL.substring(with: match.range(at: 1))
    }
}
