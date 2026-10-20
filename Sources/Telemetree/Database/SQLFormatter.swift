import Foundation

enum SQLFormatter {
    // shortcut: shallow clause formatting only; use a dialect parser if advanced formatting becomes necessary.
    private static let lineBreakKeywords: Set<String> = [
        "select", "from", "where", "group", "order", "having", "limit", "offset",
        "union", "join", "on", "and", "or"
    ]

    static func format(_ sql: String, dialect: DatabaseEngine = .mysql) -> String {
        let characters = Array(sql)
        var result = ""
        var index = 0
        var depth = 0
        var needsSpace = false

        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                needsSpace = true
                index += 1
                continue
            }

            let dashComment = character == "-" && index + 1 < characters.count && characters[index + 1] == "-"
                && (dialect != .mysql || index + 2 == characters.count || characters[index + 2].isWhitespace)
            if dashComment || (dialect == .mysql && character == "#") {
                appendSpaceIfNeeded(to: &result, needed: needsSpace)
                while index < characters.count {
                    let current = characters[index]
                    result.append(current)
                    index += 1
                    if current == "\n" { break }
                }
                needsSpace = true
                continue
            }

            if dialect == .postgres, character == "$",
               let markerEnd = characters[(index + 1)...].firstIndex(of: "$"),
               characters[(index + 1)..<markerEnd].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                let marker = Array(characters[index...markerEnd])
                var closing = markerEnd + 1
                while closing + marker.count <= characters.count,
                      Array(characters[closing..<(closing + marker.count)]) != marker {
                    closing += 1
                }
                guard closing + marker.count <= characters.count else { return sql }
                appendSpaceIfNeeded(to: &result, needed: needsSpace)
                result += String(characters[index..<(closing + marker.count)])
                index = closing + marker.count
                needsSpace = true
                continue
            }

            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                appendSpaceIfNeeded(to: &result, needed: needsSpace)
                while index < characters.count {
                    result.append(characters[index])
                    if characters[index] == "*", index + 1 < characters.count, characters[index + 1] == "/" {
                        result.append("/")
                        index += 2
                        break
                    }
                    index += 1
                }
                needsSpace = true
                continue
            }

            if character == "'" || character == "\"" || character == "`" {
                appendSpaceIfNeeded(to: &result, needed: needsSpace)
                let quote = character
                result.append(character)
                index += 1
                while index < characters.count {
                    let current = characters[index]
                    result.append(current)
                    index += 1
                    if current == "\\", quote != "`", index < characters.count {
                        result.append(characters[index])
                        index += 1
                    } else if current == quote {
                        if index < characters.count, characters[index] == quote {
                            result.append(characters[index])
                            index += 1
                        } else {
                            break
                        }
                    }
                }
                needsSpace = true
                continue
            }

            if character.isLetter || character == "_" {
                let start = index
                index += 1
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber || characters[index] == "_" || characters[index] == "$" {
                    index += 1
                }
                let word = String(characters[start..<index])
                let lowercased = word.lowercased()
                if depth == 0, lineBreakKeywords.contains(lowercased), !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result = result.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
                    if !result.hasSuffix("\n") { result += "\n" }
                    if lowercased == "and" || lowercased == "or" { result += "  " }
                } else {
                    appendSpaceIfNeeded(to: &result, needed: needsSpace)
                }
                result += SQLSyntaxHighlighter.keywords.contains(lowercased) ? word.uppercased() : word
                needsSpace = true
                continue
            }

            if character == ")" { depth = max(0, depth - 1) }
            if character == "," {
                result = result.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
                result += ", "
                needsSpace = false
                index += 1
                continue
            }

            if character != ".", character != "(", character != ")", character != ";" {
                appendSpaceIfNeeded(to: &result, needed: needsSpace)
            }
            result.append(character)
            if character == "(" { depth += 1 }
            needsSpace = ![".", "(", ";"].contains(character)
            index += 1
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendSpaceIfNeeded(to result: inout String, needed: Bool) {
        if needed, !result.isEmpty, !result.hasSuffix(" "), !result.hasSuffix("\n") {
            result.append(" ")
        }
    }
}
