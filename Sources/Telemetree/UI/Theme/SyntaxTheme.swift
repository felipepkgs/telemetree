import AppKit

/// Color scheme for SQLSyntaxHighlighter. Separate from the app-chrome
/// Theme (Vapor/Gold/Silver/Carbon) — this only affects editor token
/// colors, so it's selectable independently.
struct SyntaxTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let text: NSColor

    static func == (lhs: SyntaxTheme, rhs: SyntaxTheme) -> Bool { lhs.id == rhs.id }

    static let `default` = SyntaxTheme(
        id: "default",
        name: "Default",
        keyword: .systemPurple,
        string: .systemRed,
        number: .systemTeal,
        comment: .secondaryLabelColor,
        text: .labelColor
    )

    static let dracula = SyntaxTheme(
        id: "dracula",
        name: "Dracula",
        keyword: NSColor(calibratedRed: 1.0, green: 0.475, blue: 0.776, alpha: 1),
        string: NSColor(calibratedRed: 0.945, green: 0.980, blue: 0.549, alpha: 1),
        number: NSColor(calibratedRed: 0.741, green: 0.576, blue: 0.976, alpha: 1),
        comment: NSColor(calibratedRed: 0.384, green: 0.447, blue: 0.643, alpha: 1),
        text: NSColor(calibratedRed: 0.973, green: 0.973, blue: 0.949, alpha: 1)
    )

    static let monokai = SyntaxTheme(
        id: "monokai",
        name: "Monokai",
        keyword: NSColor(calibratedRed: 0.980, green: 0.149, blue: 0.545, alpha: 1),
        string: NSColor(calibratedRed: 0.902, green: 0.859, blue: 0.455, alpha: 1),
        number: NSColor(calibratedRed: 0.682, green: 0.506, blue: 1.0, alpha: 1),
        comment: NSColor(calibratedRed: 0.459, green: 0.443, blue: 0.373, alpha: 1),
        text: NSColor(calibratedRed: 0.973, green: 0.973, blue: 0.949, alpha: 1)
    )

    static let solarizedDark = SyntaxTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        keyword: NSColor(calibratedRed: 0.522, green: 0.600, blue: 0, alpha: 1),
        string: NSColor(calibratedRed: 0.165, green: 0.631, blue: 0.596, alpha: 1),
        number: NSColor(calibratedRed: 0.827, green: 0.212, blue: 0.510, alpha: 1),
        comment: NSColor(calibratedRed: 0.396, green: 0.482, blue: 0.514, alpha: 1),
        text: NSColor(calibratedRed: 0.514, green: 0.580, blue: 0.588, alpha: 1)
    )

    static let all: [SyntaxTheme] = [.default, .dracula, .monokai, .solarizedDark]
}
