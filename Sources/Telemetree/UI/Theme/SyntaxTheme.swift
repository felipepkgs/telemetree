import AppKit

/// GitHub's light and dark syntax palettes, independently selectable from
/// the interface appearance.
struct SyntaxTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let text: NSColor

    static func == (lhs: SyntaxTheme, rhs: SyntaxTheme) -> Bool { lhs.id == rhs.id }

    static let githubLight = SyntaxTheme(
        id: "github-light", name: "GitHub Light",
        keyword: NSColor(calibratedRed: 0.81, green: 0.13, blue: 0.18, alpha: 1),
        string: NSColor(calibratedRed: 0.04, green: 0.19, blue: 0.41, alpha: 1),
        number: NSColor(calibratedRed: 0.02, green: 0.31, blue: 0.68, alpha: 1),
        comment: NSColor(calibratedRed: 0.43, green: 0.47, blue: 0.51, alpha: 1),
        text: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.16, alpha: 1)
    )

    static let githubDark = SyntaxTheme(
        id: "github-dark", name: "GitHub Dark",
        keyword: NSColor(calibratedRed: 1, green: 0.48, blue: 0.45, alpha: 1),
        string: NSColor(calibratedRed: 0.65, green: 0.84, blue: 1, alpha: 1),
        number: NSColor(calibratedRed: 0.48, green: 0.75, blue: 1, alpha: 1),
        comment: NSColor(calibratedRed: 0.55, green: 0.59, blue: 0.64, alpha: 1),
        text: NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.96, alpha: 1)
    )

    static let all: [SyntaxTheme] = [.githubLight, .githubDark]
}
