import AppKit

/// Small, non-animated connection-state indicator in the sidebar.
final class StatusDotView: NSView {
    var isActive: Bool = false {
        didSet { updateAppearance() }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
    }

    private func updateAppearance() {
        guard isActive else {
            layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
            return
        }

        layer?.backgroundColor = NSColor.systemGreen.cgColor
    }
}
