import AppKit

/// Lightweight regex-based SQL highlighting — no parser, just keyword/
/// string/number/comment token coloring. Hooked into NSTextStorage's edit
/// processing, the standard AppKit pattern: attribute-only mutations made
/// inside didProcessEditing don't re-trigger character-edit processing, so
/// this doesn't recurse.
///
/// ponytail: re-highlights the whole document on every edit rather than
/// just the changed line. Fine for typical query sizes; if editing very
/// large SQL files ever becomes sluggish, scope the regex passes to the
/// edited paragraph range instead.
final class SQLSyntaxHighlighter: NSObject, NSTextStorageDelegate {
    /// Also used by SQLEditorViewController for keyword autocomplete.
    static let keywords: Set<String> = [
        "select", "from", "where", "join", "inner", "left", "right", "outer",
        "full", "on", "and", "or", "not", "null", "is", "in", "like",
        "between", "order", "by", "group", "having", "limit", "offset", "as",
        "distinct", "insert", "into", "values", "update", "set", "delete",
        "create", "table", "alter", "drop", "index", "primary", "key",
        "foreign", "references", "default", "unique", "constraint",
        "auto_increment", "begin", "commit", "rollback", "transaction",
        "union", "all", "exists", "case", "when", "then", "else", "end",
        "desc", "asc", "count", "sum", "avg", "min", "max", "database",
        "databases", "show", "tables", "use", "if", "view", "trigger",
        "procedure", "function", "return", "returns", "declare", "cascade",
        "truncate", "explain", "describe", "with", "over", "partition"
    ]

    private static let identifierRegex = try! NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\b"#)
    private static let stringRegex = try! NSRegularExpression(pattern: #"'([^'\\]|\\.)*'|"([^"\\]|\\.)*""#)
    private static let numberRegex = try! NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#)
    private static let lineCommentRegex = try! NSRegularExpression(pattern: #"--[^\n]*"#)
    private static let blockCommentRegex = try! NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#)
    private static let backtickRegex = try! NSRegularExpression(pattern: #"`[^`]*`"#)

    var font: NSFont
    var theme: SyntaxTheme

    private var keywordFont: NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    init(font: NSFont? = nil, theme: SyntaxTheme = .default) {
        self.font = font ?? FontLibrary.mono(12)
        self.theme = theme
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlight(textStorage)
    }

    func highlight(_ textStorage: NSTextStorage) {
        let text = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        guard fullRange.length > 0 else { return }
        let string = text as String

        textStorage.beginEditing()
        textStorage.setAttributes([.font: font, .foregroundColor: theme.text], range: fullRange)

        for match in Self.numberRegex.matches(in: string, range: fullRange) {
            textStorage.addAttribute(.foregroundColor, value: theme.number, range: match.range)
        }

        for match in Self.backtickRegex.matches(in: string, range: fullRange) {
            textStorage.addAttribute(.foregroundColor, value: theme.number, range: match.range)
        }

        for match in Self.identifierRegex.matches(in: string, range: fullRange) {
            let word = text.substring(with: match.range).lowercased()
            guard Self.keywords.contains(word) else { continue }
            textStorage.addAttribute(.foregroundColor, value: theme.keyword, range: match.range)
            textStorage.addAttribute(.font, value: keywordFont, range: match.range)
        }

        for match in Self.stringRegex.matches(in: string, range: fullRange) {
            textStorage.addAttribute(.foregroundColor, value: theme.string, range: match.range)
            textStorage.addAttribute(.font, value: font, range: match.range)
        }

        for match in Self.lineCommentRegex.matches(in: string, range: fullRange) {
            textStorage.addAttribute(.foregroundColor, value: theme.comment, range: match.range)
            textStorage.addAttribute(.font, value: font, range: match.range)
        }

        for match in Self.blockCommentRegex.matches(in: string, range: fullRange) {
            textStorage.addAttribute(.foregroundColor, value: theme.comment, range: match.range)
            textStorage.addAttribute(.font, value: font, range: match.range)
        }

        textStorage.endEditing()
    }
}
