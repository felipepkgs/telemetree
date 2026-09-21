import AppKit

/// A small fixed palette for color-labeling queries/folders/snippets in
/// the sidebar, matching the "8 colors is fine" scope — not a custom
/// color picker.
enum LabelColor: String, CaseIterable, Codable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var name: String {
        rawValue.capitalized
    }

    var color: NSColor {
        switch self {
        case .red: return NSColor.systemRed
        case .orange: return NSColor.systemOrange
        case .yellow: return NSColor.systemYellow
        case .green: return NSColor.systemGreen
        case .blue: return NSColor.systemBlue
        case .purple: return NSColor.systemPurple
        case .pink: return NSColor.systemPink
        case .gray: return NSColor.systemGray
        }
    }

    /// A small filled circle for use as an NSMenuItem's image.
    func swatchImage(diameter: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
        image.unlockFocus()
        return image
    }
}
