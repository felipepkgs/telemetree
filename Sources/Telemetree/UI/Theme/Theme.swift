import AppKit

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let appearanceName: NSAppearance.Name
    let palette: DesignTokens.Palette
    let cornerRadius: CGFloat

    var barFill: NSColor { palette.elevated }
    var barBorder: NSColor { palette.separator }
    var activeSegmentFill: NSColor { palette.selection }
    var activeSegmentText: NSColor { palette.accent }

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id }

    static let light = Theme(
        id: "light",
        name: "Light",
        appearanceName: .aqua,
        palette: DesignTokens.light,
        cornerRadius: 5
    )

    static let dark = Theme(
        id: "dark",
        name: "Dark",
        appearanceName: .darkAqua,
        palette: DesignTokens.midnight,
        cornerRadius: 5
    )

    static let all: [Theme] = [.light, .dark]
}
