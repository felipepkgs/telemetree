import AppKit

/// One tab in the document tab bar: a title plus a close button.
@MainActor
final class TabButtonView: NSView {
    private let onSelect: () -> Void
    private let onClose: () -> Void

    init(title: String, isActive: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor

        let label = NSTextField(labelWithString: title)
        label.font = FontLibrary.sans(12, weight: isActive ? .semibold : .regular)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(
            image: AppIcon.close.image,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 160),

            closeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 12),
            closeButton.heightAnchor.constraint(equalToConstant: 12),

            heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func closeTapped() {
        onClose()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect()
    }
}
