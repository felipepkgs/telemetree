import AppKit

/// Vapor family only — the other theme families from the shared
/// cross-app spec (Meniscus/Ulm/Instrument/Unibody) aren't happening
/// here, full stop; see SPEC.md "Cross-app theme system" for the
/// decision. Adapted from a Touch Bar overlay's theme language onto Telemetree's
/// actual chrome: bar/chip fill+border on toolbars, the active-tab pill,
/// and the connection-status dot (the closest analogue to the original
/// "touch dot").
///
/// ponytail: Carbon Fiber's woven diagonal-gradient texture from the
/// source spec is skipped — just the dark tint + red accent, which is
/// the theme's real identity per the spec's own "one accent per theme"
/// rule. Add the weave later via a CAGradientLayer pattern if wanted.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let barFill: NSColor
    let barBorder: NSColor
    let activeSegmentFill: NSColor
    let activeSegmentText: NSColor
    let dotGradientStart: NSColor
    let dotGradientEnd: NSColor
    let dotGlow: NSColor
    let cornerRadius: CGFloat
    let pulseEnabled: Bool

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id }

    /// The color bars should actually paint with — same as `barFill`
    /// except on Vapor Carbon, which gets the woven texture instead of a
    /// flat fill. Chips (the tab pill) intentionally don't use this —
    /// they read `activeSegmentFill` directly, flat, per the source spec.
    var barFillPaint: NSColor {
        id == "vapor-carbon" ? CarbonWeaveTexture.patternColor(base: barFill) : barFill
    }

    static let vapor = Theme(
        id: "vapor",
        name: "Vapor",
        barFill: NSColor.white.withAlphaComponent(0.05),
        barBorder: NSColor.white.withAlphaComponent(0.08),
        activeSegmentFill: NSColor.white.withAlphaComponent(0.16),
        activeSegmentText: .white,
        dotGradientStart: NSColor(calibratedRed: 0.545, green: 1.0, blue: 0.671, alpha: 1),
        dotGradientEnd: NSColor(calibratedRed: 0.188, green: 0.820, blue: 0.345, alpha: 1),
        dotGlow: NSColor(calibratedRed: 0.188, green: 0.820, blue: 0.345, alpha: 0.65),
        cornerRadius: 9,
        pulseEnabled: true
    )

    static let vaporGold = Theme(
        id: "vapor-gold",
        name: "Vapor — Gold",
        barFill: NSColor(calibratedRed: 1, green: 0.839, blue: 0.510, alpha: 0.14),
        barBorder: NSColor.white.withAlphaComponent(0.08),
        activeSegmentFill: NSColor(calibratedRed: 1, green: 0.839, blue: 0.510, alpha: 0.20),
        activeSegmentText: NSColor(calibratedRed: 1, green: 0.957, blue: 0.871, alpha: 1),
        dotGradientStart: NSColor(calibratedRed: 1, green: 0.910, blue: 0.682, alpha: 1),
        dotGradientEnd: NSColor(calibratedRed: 0.851, green: 0.651, blue: 0.235, alpha: 1),
        dotGlow: NSColor(calibratedRed: 0.851, green: 0.651, blue: 0.235, alpha: 0.6),
        cornerRadius: 9,
        pulseEnabled: true
    )

    static let vaporSilver = Theme(
        id: "vapor-silver",
        name: "Vapor — Silver",
        barFill: NSColor(calibratedRed: 0.902, green: 0.925, blue: 0.949, alpha: 0.12),
        barBorder: NSColor.white.withAlphaComponent(0.08),
        activeSegmentFill: NSColor(calibratedRed: 0.902, green: 0.925, blue: 0.949, alpha: 0.18),
        activeSegmentText: NSColor(calibratedRed: 0.961, green: 0.973, blue: 0.984, alpha: 1),
        dotGradientStart: .white,
        dotGradientEnd: NSColor(calibratedRed: 0.725, green: 0.761, blue: 0.800, alpha: 1),
        dotGlow: NSColor.white.withAlphaComponent(0.5),
        cornerRadius: 9,
        pulseEnabled: true
    )

    static let vaporCarbon = Theme(
        id: "vapor-carbon",
        name: "Vapor — Carbon Fiber",
        barFill: NSColor(calibratedRed: 0.039, green: 0.039, blue: 0.047, alpha: 0.35),
        barBorder: NSColor.white.withAlphaComponent(0.06),
        activeSegmentFill: NSColor(calibratedRed: 0.784, green: 0.118, blue: 0.227, alpha: 0.24),
        activeSegmentText: NSColor(calibratedRed: 1, green: 0.85, blue: 0.85, alpha: 1),
        dotGradientStart: NSColor(calibratedRed: 1, green: 0.42, blue: 0.341, alpha: 1),
        dotGradientEnd: NSColor(calibratedRed: 0.784, green: 0.118, blue: 0.227, alpha: 1),
        dotGlow: NSColor(calibratedRed: 0.784, green: 0.118, blue: 0.227, alpha: 0.6),
        cornerRadius: 9,
        pulseEnabled: true
    )

    static let all: [Theme] = [.vapor, .vaporGold, .vaporSilver, .vaporCarbon]
}
