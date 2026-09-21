import AppKit

/// A minimal completion popup — deliberately not `NSTextView.complete(_:)`.
/// That built-in mechanism auto-inserts (and re-cases) the sole match into
/// the document as soon as typing narrows to one candidate, with no explicit
/// accept step, and there's no supported way to suppress just that part of
/// it. This popup only ever touches the document when the caller explicitly
/// accepts a candidate (see SQLEditorViewController's Tab handling) — typing
///, including a trailing space, never mutates anything beyond what was
/// actually typed.
@MainActor
final class CompletionPopup {
    private let window: NSWindow
    private let stackView = NSStackView()
    private let outerStack = NSStackView()
    private(set) var candidates: [String] = []
    private(set) var selectedIndex = 0
    private var rowLabels: [NSTextField] = []

    private static let maxVisibleRows = 8
    private static let rowHeight: CGFloat = 20

    var isVisible: Bool { window.isVisible }

    var selectedCandidate: String? {
        candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil
    }

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor

        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

        let divider = NSBox()
        divider.boxType = .separator

        // Issue #8: without this, there's no on-screen indication of which
        // key accepts a suggestion or that anything other than Tab is safe
        // to press — muted text rather than Icons8 kbd glyphs, to avoid
        // pulling in new icon assets just for two key names.
        let hint = NSTextField(labelWithString: "⇥ accept · space dismisses")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        let hintRow = NSView()
        hintRow.translatesAutoresizingMaskIntoConstraints = false
        hintRow.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: hintRow.leadingAnchor, constant: 10),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: hintRow.trailingAnchor, constant: -10),
            hint.topAnchor.constraint(equalTo: hintRow.topAnchor, constant: 3),
            hint.bottomAnchor.constraint(equalTo: hintRow.bottomAnchor, constant: -3)
        ])

        outerStack.orientation = .vertical
        outerStack.alignment = .width
        outerStack.spacing = 0
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.addArrangedSubview(stackView)
        outerStack.addArrangedSubview(divider)
        outerStack.addArrangedSubview(hintRow)
        background.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: background.topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            outerStack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: background.trailingAnchor)
        ])
        window.contentView = background
    }

    /// `screenPoint` is the top-left corner the popup should hang from —
    /// typically just below the caret, in screen coordinates.
    func show(candidates: [String], at screenPoint: NSPoint, parent: NSWindow) {
        self.candidates = candidates
        selectedIndex = 0
        rebuildRows()

        let size = outerStack.fittingSize
        window.setContentSize(NSSize(width: max(size.width, 160), height: size.height))
        window.setFrameTopLeftPoint(screenPoint)

        if window.parent !== parent {
            parent.addChildWindow(window, ordered: .above)
        }
        window.orderFront(nil)
    }

    func hide() {
        guard window.isVisible || window.parent != nil else { return }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    func moveSelection(by delta: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + candidates.count) % candidates.count
        updateHighlight()
    }

    private func rebuildRows() {
        rowLabels.forEach { $0.removeFromSuperview() }
        rowLabels.removeAll()
        for candidate in candidates.prefix(Self.maxVisibleRows) {
            let label = NSTextField(labelWithString: candidate)
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.drawsBackground = true
            label.backgroundColor = .clear
            label.translatesAutoresizingMaskIntoConstraints = false
            label.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            stackView.addArrangedSubview(label)
            rowLabels.append(label)
        }
        updateHighlight()
    }

    private func updateHighlight() {
        for (i, label) in rowLabels.enumerated() {
            let selected = i == selectedIndex
            label.backgroundColor = selected ? .selectedContentBackgroundColor : .clear
            label.textColor = selected ? .selectedMenuItemTextColor : .labelColor
        }
    }
}
