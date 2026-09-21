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
        stackView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: background.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: background.trailingAnchor)
        ])
        window.contentView = background
    }

    /// `screenPoint` is the top-left corner the popup should hang from —
    /// typically just below the caret, in screen coordinates.
    func show(candidates: [String], at screenPoint: NSPoint, parent: NSWindow) {
        self.candidates = candidates
        selectedIndex = 0
        rebuildRows()

        let size = stackView.fittingSize
        window.setContentSize(NSSize(width: max(size.width, 140), height: size.height))
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
