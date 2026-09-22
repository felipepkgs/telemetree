import AppKit

/// Drives a Tab-only completion popup for a single NSTextView — keywords
/// always, real table names (when `tableNamesProvider` returns any) right
/// after FROM/JOIN/INTO/UPDATE/etc., and real column names everywhere
/// else. Column suggestions come from two different sources depending on
/// whether the current statement has a FROM yet:
///   - FROM present: plain column names from the referenced table(s)
///     (columnNamesProvider), e.g. typing "id" after "SELECT " suggests
///     "id" — same as before.
///   - FROM absent: qualified "table.column" suggestions across every
///     table this connection has cached columns for (allColumnsProvider).
///     Accepting one inserts just the column name *and* appends a
///     `FROM `table`` clause to the end of the statement — the caret
///     stays exactly where the column was accepted, not wherever FROM
///     landed.
/// Shared by the main SQL editor and the snippet editor so both get the
/// same behavior instead of two copies drifting apart; the snippet editor
/// leaves all three providers at their defaults (no schema — snippets
/// aren't tied to one connection).
///
/// Deliberately not `NSTextView.complete(_:)` — see CompletionPopup's own
/// doc comment for why.
@MainActor
final class SQLCompletionController {
    private unowned let textView: NSTextView
    private let popup = CompletionPopup()
    private var completionRange: NSRange?
    private var currentCandidates: [Candidate] = []
    /// Where the caret was expected to be after the edit that last
    /// showed/updated the popup — see `selectionDidChange`.
    private var completionAnchor: Int?

    private struct Candidate {
        let display: String
        let insertText: String
        /// Non-nil only for a qualified "table.column" suggestion offered
        /// before a FROM exists — accepting it also appends that FROM.
        let impliedFromTable: String?
    }

    /// Real table names for the identifier position, real case, filtered
    /// by prefix by the caller as needed — supplied fresh each call since
    /// it's cheap (a stored array lookup) and avoids this controller
    /// needing to know anything about connections/caching.
    var tableNamesProvider: () -> [String] = { [] }

    /// Real column names for the given (best-effort) table names —
    /// referencedTableNames() extracts those from the statement under the
    /// caret via a keyword regex, not a real parser (same tradeoff as
    /// DestructiveSQLGuard/SQLStatementLocator elsewhere in this app).
    var columnNamesProvider: (_ tables: [String]) -> [String] = { _ in [] }

    /// Every (table, column) pair this connection currently has columns
    /// cached for — used only when the statement has no FROM yet, so
    /// there's no single table to scope plain column completion to.
    /// Best-effort: whatever's been fetched lazily so far (from earlier
    /// completions or sidebar browsing), not an eager full-schema fetch.
    var allColumnsProvider: () -> [(table: String, column: String)] = { [] }

    init(textView: NSTextView) {
        self.textView = textView
    }

    func textDidChange() {
        updateCompletions()
    }

    func hide() {
        completionRange = nil
        completionAnchor = nil
        currentCandidates = []
        popup.hide()
    }

    /// Dismisses the popup if the caret ended up somewhere it didn't
    /// expect — arrow keys past it, a mouse click elsewhere, anything
    /// that isn't the text edit that just showed/updated it (that path
    /// already moves completionAnchor to match, via showCompletions,
    /// before this could ever see a mismatch).
    func selectionDidChange() {
        guard popup.isVisible, textView.selectedRange().location != completionAnchor else { return }
        hide()
    }

    /// Intercepts Tab/arrows/Escape while the popup is visible so Tab is
    /// the only key that ever accepts a suggestion — everything else
    /// (including Space, which isn't a command selector at all and so
    /// never reaches here) behaves exactly as if the popup weren't there.
    func doCommandBy(_ commandSelector: Selector) -> Bool {
        guard popup.isVisible else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            acceptCompletion()
            return true
        case #selector(NSResponder.moveDown(_:)):
            popup.moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            popup.moveSelection(by: -1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }

    /// Keywords immediately followed by an identifier (table/db/column
    /// name), not another keyword — completing against the keyword list
    /// there is actively wrong, not just unhelpful: a real table named
    /// "order" (a keyword itself, like several common English words) would
    /// get suggested as "ORDER" mid-query, a different name than the one
    /// that exists. Real table names (tableNamesProvider) are suggested
    /// there instead.
    private static let identifierPositionKeywords: Set<String> = [
        "from", "join", "into", "update", "table", "tables", "database",
        "databases", "view", "index", "trigger", "procedure", "function"
    ]

    private static let tableReferenceRegex = try! NSRegularExpression(
        pattern: #"\b(?:FROM|JOIN)\s+(?:`?[A-Za-z_][A-Za-z0-9_]*`?\.)?`?([A-Za-z_][A-Za-z0-9_]*)`?"#,
        options: .caseInsensitive
    )

    private func updateCompletions() {
        guard textView.selectedRange().length == 0 else {
            hide()
            return
        }
        let caret = textView.selectedRange().location
        let wordRange = currentWordRange(endingAt: caret)
        // Where to look for a preceding "FROM"/"JOIN"/etc: the start of
        // the word being typed, or the caret itself when there's no word
        // yet (precedingWordExpectsIdentifier already skips back over
        // whitespace on its own, so "FROM |" with the caret right after
        // the space still finds "FROM").
        let identifierCheckLocation = wordRange?.location ?? caret
        let partial = wordRange.map { (textView.string as NSString).substring(with: $0).lowercased() } ?? ""

        let candidates: [Candidate]
        if precedingWordExpectsIdentifier(before: identifierCheckLocation) {
            // Right after FROM/JOIN/etc, list every table immediately —
            // even with nothing typed yet — rather than waiting for a
            // prefix to filter against.
            candidates = tableNamesProvider()
                .filter { $0.lowercased().hasPrefix(partial) }
                .sorted()
                .map { Candidate(display: $0, insertText: $0, impliedFromTable: nil) }
        } else {
            guard let wordRange, wordRange.length > 0 else {
                hide()
                return
            }
            let keywordMatches = SQLSyntaxHighlighter.keywords
                .filter { $0.hasPrefix(partial) }
                .map { Candidate(display: $0.uppercased(), insertText: $0.uppercased(), impliedFromTable: nil) }

            let tables = referencedTableNames()
            let columnMatches: [Candidate]
            if !tables.isEmpty {
                // FROM already present — plain column names scoped to
                // whatever tables it references.
                columnMatches = columnNamesProvider(tables)
                    .filter { $0.lowercased().hasPrefix(partial) }
                    .map { Candidate(display: $0, insertText: $0, impliedFromTable: nil) }
            } else {
                // No FROM yet — offer every known column, qualified by
                // table, and wire up the auto-FROM side effect.
                columnMatches = allColumnsProvider()
                    .filter { $0.column.lowercased().hasPrefix(partial) || $0.table.lowercased().hasPrefix(partial) }
                    .map { Candidate(display: "\($0.table).\($0.column)", insertText: $0.column, impliedFromTable: $0.table) }
            }
            candidates = (keywordMatches + columnMatches)
                .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
        }
        // Nothing left to suggest once the only match is exactly what's
        // already typed (e.g. right after accepting one).
        guard !candidates.isEmpty, !(candidates.count == 1 && candidates[0].insertText.lowercased() == partial) else {
            hide()
            return
        }
        completionRange = wordRange ?? NSRange(location: caret, length: 0)
        showCompletions(candidates)
    }

    /// Best-effort table names referenced by the statement under the
    /// caret (not the whole buffer — a multi-statement document shouldn't
    /// suggest columns from an unrelated statement elsewhere in it).
    private func referencedTableNames() -> [String] {
        let fullText = textView.string
        let scopeText = SQLStatementLocator.statement(containing: textView.selectedRange().location, in: fullText)?.text ?? fullText
        let nsScope = scopeText as NSString
        let matches = Self.tableReferenceRegex.matches(in: scopeText, range: NSRange(location: 0, length: nsScope.length))
        var seen = Set<String>()
        var names: [String] = []
        for match in matches where match.numberOfRanges > 1 {
            let name = nsScope.substring(with: match.range(at: 1))
            guard seen.insert(name.lowercased()).inserted else { continue }
            names.append(name)
        }
        return names
    }

    private func showCompletions(_ candidates: [Candidate]) {
        guard let range = completionRange, let window = textView.window else { return }
        currentCandidates = candidates
        let caretRange = NSRange(location: NSMaxRange(range), length: 0)
        let screenRect = textView.firstRect(forCharacterRange: caretRange, actualRange: nil)
        completionAnchor = NSMaxRange(range)
        popup.show(candidates: candidates.map(\.display), at: NSPoint(x: screenRect.minX, y: screenRect.minY), parent: window)
    }

    private func acceptCompletion() {
        guard let range = completionRange, currentCandidates.indices.contains(popup.selectedIndex) else { return }
        let candidate = currentCandidates[popup.selectedIndex]
        hide()
        // Insert the FROM clause FIRST, not after — its insertion point is
        // always later in the buffer than `range`, so inserting there
        // doesn't shift `range`'s own coordinates, and the field insert
        // below (done last) naturally leaves the caret exactly where it
        // belongs on its own. No separate "restore the caret" step needed
        // — and nothing to race against, unlike inserting the field first
        // and trying to move the caret back afterward.
        if let table = candidate.impliedFromTable {
            insertFromClause(for: table, statementCaret: range.location)
        }
        textView.insertText(candidate.insertText, replacementRange: range)
    }

    /// Inserts ` FROM `table`` at the end of the statement containing
    /// `statementCaret` — before a trailing ";" if there is one.
    private func insertFromClause(for table: String, statementCaret: Int) {
        guard let statement = SQLStatementLocator.statement(containing: statementCaret, in: textView.string) else { return }
        let nsText = textView.string as NSString
        var insertAt = NSMaxRange(statement.range)
        if insertAt > statement.range.location, nsText.substring(with: NSRange(location: insertAt - 1, length: 1)) == ";" {
            insertAt -= 1
        }
        while insertAt > statement.range.location,
              nsText.substring(with: NSRange(location: insertAt - 1, length: 1)).rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            insertAt -= 1
        }
        textView.insertText(" FROM `\(table)`", replacementRange: NSRange(location: insertAt, length: 0))
    }

    private func currentWordRange(endingAt location: Int) -> NSRange? {
        let text = textView.string as NSString
        guard location > 0, location <= text.length else { return nil }
        var start = location
        while start > 0 {
            let char = text.substring(with: NSRange(location: start - 1, length: 1))
            guard char.rangeOfCharacter(from: .alphanumerics.union(CharacterSet(charactersIn: "_"))) != nil else { break }
            start -= 1
        }
        guard start < location else { return nil }
        return NSRange(location: start, length: location - start)
    }

    private func precedingWordExpectsIdentifier(before location: Int) -> Bool {
        let text = textView.string as NSString
        guard location > 0 else { return false }
        // A leading "." (as in `db.table`) always means an identifier
        // comes next, regardless of what preceded that.
        if location > 0, text.substring(with: NSRange(location: location - 1, length: 1)) == "." {
            return true
        }
        var end = location
        while end > 0, text.substring(with: NSRange(location: end - 1, length: 1)) == " " {
            end -= 1
        }
        var start = end
        while start > 0 {
            let char = text.substring(with: NSRange(location: start - 1, length: 1))
            guard char.rangeOfCharacter(from: .alphanumerics.union(CharacterSet(charactersIn: "_"))) != nil else { break }
            start -= 1
        }
        guard start < end else { return false }
        let word = text.substring(with: NSRange(location: start, length: end - start)).lowercased()
        return Self.identifierPositionKeywords.contains(word)
    }
}
