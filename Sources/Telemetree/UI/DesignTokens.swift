import AppKit

/// Shared spacing, shape, and appearance tokens for the AppKit interface.
enum DesignTokens {
    struct Palette {
        let window: NSColor
        let sidebar: NSColor
        let editor: NSColor
        let elevated: NSColor
        let accent: NSColor
        let text: NSColor
        let secondaryText: NSColor
        let separator: NSColor
        let selection: NSColor
        let alternateRow: NSColor
    }

    static let midnight = Palette(
        window: NSColor(calibratedRed: 17 / 255, green: 21 / 255, blue: 29 / 255, alpha: 1),
        sidebar: NSColor(calibratedRed: 23 / 255, green: 28 / 255, blue: 38 / 255, alpha: 1),
        editor: NSColor(calibratedRed: 28 / 255, green: 34 / 255, blue: 46 / 255, alpha: 1),
        elevated: NSColor(calibratedRed: 37 / 255, green: 45 / 255, blue: 59 / 255, alpha: 1),
        accent: NSColor(calibratedRed: 162 / 255, green: 175 / 255, blue: 255 / 255, alpha: 1),
        text: NSColor(calibratedRed: 231 / 255, green: 235 / 255, blue: 245 / 255, alpha: 1),
        secondaryText: NSColor(calibratedRed: 157 / 255, green: 167 / 255, blue: 186 / 255, alpha: 1),
        separator: NSColor(calibratedRed: 49 / 255, green: 58 / 255, blue: 75 / 255, alpha: 1),
        selection: NSColor(calibratedRed: 55 / 255, green: 65 / 255, blue: 104 / 255, alpha: 1),
        alternateRow: NSColor(calibratedRed: 32 / 255, green: 39 / 255, blue: 52 / 255, alpha: 1)
    )

    static let light = Palette(
        window: NSColor(calibratedRed: 245 / 255, green: 247 / 255, blue: 251 / 255, alpha: 1),
        sidebar: NSColor(calibratedRed: 239 / 255, green: 242 / 255, blue: 248 / 255, alpha: 1),
        editor: NSColor.white,
        elevated: NSColor(calibratedRed: 232 / 255, green: 236 / 255, blue: 244 / 255, alpha: 1),
        accent: NSColor(calibratedRed: 61 / 255, green: 83 / 255, blue: 177 / 255, alpha: 1),
        text: NSColor(calibratedRed: 29 / 255, green: 36 / 255, blue: 51 / 255, alpha: 1),
        secondaryText: NSColor(calibratedRed: 87 / 255, green: 97 / 255, blue: 115 / 255, alpha: 1),
        separator: NSColor(calibratedRed: 215 / 255, green: 220 / 255, blue: 230 / 255, alpha: 1),
        selection: NSColor(calibratedRed: 225 / 255, green: 231 / 255, blue: 255 / 255, alpha: 1),
        alternateRow: NSColor(calibratedRed: 243 / 255, green: 245 / 255, blue: 249 / 255, alpha: 1)
    )

    // Spacing scale (shadcn/Tailwind's 4px base unit).
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 20

    // Corner radius scale — shadcn's default --radius is 8px, with
    // sm/md derived from it. AppKit's own controls (NSGridView rows,
    // NSButton) are already small, so this popup/dialog scale stays
    // modest rather than copying the 8px default everywhere.
    static let radiusSM: CGFloat = 4
    static let radiusMD: CGFloat = 6

    static let borderWidth: CGFloat = 1
}
