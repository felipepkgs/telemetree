import AppKit

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let appearanceName: NSAppearance.Name
    let barFill: NSColor
    let barBorder: NSColor
    let activeSegmentFill: NSColor
    let activeSegmentText: NSColor
    let cornerRadius: CGFloat

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id }

    static let light = Theme(
        id: "light",
        name: "Light",
        appearanceName: .aqua,
        barFill: NSColor(calibratedWhite: 0.97, alpha: 1),
        barBorder: NSColor(calibratedWhite: 0.87, alpha: 1),
        activeSegmentFill: NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.98, alpha: 1),
        activeSegmentText: NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.55, alpha: 1),
        cornerRadius: 5
    )

    static let dark = Theme(
        id: "dark",
        name: "Dark",
        appearanceName: .darkAqua,
        barFill: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.17, alpha: 1),
        barBorder: NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.31, alpha: 1),
        activeSegmentFill: NSColor(calibratedRed: 0.15, green: 0.27, blue: 0.42, alpha: 1),
        activeSegmentText: NSColor(calibratedRed: 0.65, green: 0.79, blue: 0.98, alpha: 1),
        cornerRadius: 5
    )

    static let all: [Theme] = [.light, .dark]
}
