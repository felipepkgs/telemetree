import AppKit

/// Drives a Tab-only completion popup for a single NSTextView — keywords
/// always, plus (when `tableNamesProvider` returns any) real table names
/// right after FROM/JOIN/INTO/UPDATE/etc. Shared by the main SQL editor
/// and the snippet editor so both get the same behavior instead of two
/// copies drifting apart; the snippet editor just leaves the provider at
/// its default (no tables — snippets aren't tied to one connection).
///
/// Deliberately not `NSTextView.complete(_:)` — see CompletionPopup's own
/// doc comment for why.
@MainActor
final class SQLCompletionController {
    private unowned let textView: NSTextView
    private let popup = CompletionPopup()
    private var completionRange: NSRange?

    /// Real table names for the identifier position, real case, filtered
    /// by prefix by the caller as needed — supplied fresh each call since
    /// it's cheap (a stored array lookup) and avoids this controller
    /// needing to know anything about connections/caching.
    var tableNamesProvider: () -> [String] = { [] }

    init(textView: NSTextView) {
        self.textView = textView
    }

    func textDidChange() {
        updateCompletions()
    }

    func hide() {
        completionRange = nil
        popup.hide()
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

    private func updateCompletions() {
        guard textView.selectedRange().length == 0,
              let range = currentWordRange(endingAt: textView.selectedRange().location),
              range.length > 0 else {
            hide()
            return
        }
        let partial = (textView.string as NSString).substring(with: range).lowercased()
        let candidates: [String]
        if precedingWordExpectsIdentifier(before: range.location) {
            candidates = tableNamesProvider().filter { $0.lowercased().hasPrefix(partial) }.sorted()
        } else {
            candidates = SQLSyntaxHighlighter.keywords
                .filter { $0.hasPrefix(partial) }
                .sorted()
                .map { $0.uppercased() }
        }
        // Nothing left to suggest once the only match is exactly what's
        // already typed (e.g. right after accepting one).
        guard !candidates.isEmpty, !(candidates.count == 1 && candidates[0].lowercased() == partial) else {
            hide()
            return
        }
        completionRange = range
        showCompletions(candidates)
    }

    private func showCompletions(_ candidates: [String]) {
        guard let range = completionRange, let window = textView.window else { return }
        let caretRange = NSRange(location: NSMaxRange(range), length: 0)
        let screenRect = textView.firstRect(forCharacterRange: caretRange, actualRange: nil)
        popup.show(candidates: candidates, at: NSPoint(x: screenRect.minX, y: screenRect.minY), parent: window)
    }

    private func acceptCompletion() {
        guard let range = completionRange, let candidate = popup.selectedCandidate else { return }
        textView.insertText(candidate, replacementRange: range)
        hide()
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
