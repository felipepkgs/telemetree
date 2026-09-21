import Foundation

/// Splits editor text into individual SQL statements on top-level `;`
/// boundaries, ignoring semicolons inside string literals or comments.
/// This is what makes "Run" scope to just the statement the caret is in
/// (or the actual selection) instead of the whole buffer — critical when
/// the editor holds more than one statement, since blindly sending the
/// full buffer could execute an unrelated, possibly destructive,
/// statement sitting elsewhere in the same document.
enum SQLStatementLocator {
    struct Statement {
        let range: NSRange
        let text: String
    }

    private static let stringRegex = try! NSRegularExpression(pattern: #"'([^'\\]|\\.)*'|"([^"\\]|\\.)*""#)
    private static let lineCommentRegex = try! NSRegularExpression(pattern: #"--[^\n]*"#)
    private static let blockCommentRegex = try! NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#)

    static func statements(in sql: String) -> [Statement] {
        let nsString = sql as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        guard fullRange.length > 0 else { return [] }
        let masked = maskedRanges(in: sql, fullRange: fullRange)

        var result: [Statement] = []
        var searchStart = 0
        var statementStart = 0

        while searchStart < nsString.length {
            let remaining = NSRange(location: searchStart, length: nsString.length - searchStart)
            let found = nsString.range(of: ";", range: remaining)
            guard found.location != NSNotFound else { break }

            if masked.contains(where: { NSLocationInRange(found.location, $0) }) {
                searchStart = found.location + 1
                continue
            }

            let statementRange = NSRange(location: statementStart, length: found.location - statementStart + 1)
            append(statementRange, nsString: nsString, to: &result)
            statementStart = found.location + 1
            searchStart = statementStart
        }

        if statementStart < nsString.length {
            let statementRange = NSRange(location: statementStart, length: nsString.length - statementStart)
            append(statementRange, nsString: nsString, to: &result)
        }
        return result
    }

    /// The statement the caret at `location` sits inside. Falls back to
    /// the nearest preceding statement (caret parked in trailing
    /// whitespace/on the closing `;`), then the first statement.
    static func statement(containing location: Int, in sql: String) -> Statement? {
        let all = statements(in: sql)
        if let match = all.first(where: { NSLocationInRange(location, $0.range) }) {
            return match
        }
        return all.last(where: { $0.range.location <= location }) ?? all.first
    }

    private static func append(_ range: NSRange, nsString: NSString, to result: inout [Statement]) {
        let text = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        result.append(Statement(range: range, text: text))
    }

    private static func maskedRanges(in sql: String, fullRange: NSRange) -> [NSRange] {
        [stringRegex, lineCommentRegex, blockCommentRegex]
            .flatMap { $0.matches(in: sql, range: fullRange) }
            .map(\.range)
    }
}
