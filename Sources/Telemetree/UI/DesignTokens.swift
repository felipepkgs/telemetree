import AppKit

/// Shared visual constants for the app's secondary chrome — dialogs
/// (New Connection, Save Query As, About) and standalone popups
/// (CompletionPopup). Deliberately NOT used by Theme.swift/ThemeStore or
/// anything that reads `theme.barFillPaint`/`barBorder` — the Vapor
/// theme family is the app's own deliberate branding for the main
/// editor/toolbar/tab chrome and stays exactly as it is.
///
/// Loosely modeled on shadcn/ui's design language — a small consistent
/// radius scale, subtle 1px borders over shadows, a restrained neutral
/// palette — translated to AppKit's own semantic NSColor API (not
/// hardcoded hex) so light/dark mode keeps working for free, the same
/// way shadcn itself is built on semantic CSS variables rather than
/// fixed colors.
enum DesignTokens {
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

    // Semantic colors, not a fixed hex palette.
    static let border = NSColor.separatorColor
}
