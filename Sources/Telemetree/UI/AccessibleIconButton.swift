import AppKit

/// NSButton's default `accessibilityLabel()` returns its `.title` and
/// ignores `setAccessibilityLabel(_:)` entirely — confirmed by directly
/// inspecting the live AXUIElement tree (AppleScript's System Events
/// masked this: its "description" property reads AXRoleDescription, a
/// generic per-role string like "button", not the actual accessibility
/// label). For an icon-only button with no title, that leaves VoiceOver
/// with nothing to announce. Overriding the getter is what actually works.
final class AccessibleIconButton: NSButton {
    var accessibilityLabelOverride: String?

    override func accessibilityLabel() -> String? {
        accessibilityLabelOverride ?? super.accessibilityLabel()
    }
}
