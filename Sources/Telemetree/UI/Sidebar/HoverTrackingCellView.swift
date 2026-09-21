import AppKit

/// An NSTableCellView that reports mouse hover so the sidebar can show a
/// delete button only while the pointer is over a row.
final class HoverTrackingCellView: NSTableCellView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    /// NSTableCellView computes its own accessibility label from
    /// `.textField.stringValue` and ignores `setAccessibilityLabel` calls
    /// on the cell itself — confirmed by inspecting the live AX tree, not
    /// guessed. Overriding the getter directly is what actually sticks.
    var accessibilityDescriptionOverride: String?

    override func accessibilityLabel() -> String? {
        accessibilityDescriptionOverride ?? super.accessibilityLabel()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
