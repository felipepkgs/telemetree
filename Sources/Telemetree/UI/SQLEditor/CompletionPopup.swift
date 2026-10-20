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
    struct Item {
        let title: String
        let detail: String
    }
    private let window: NSWindow
    private let stackView = NSStackView()
    private let outerStack = NSStackView()
    private(set) var candidates: [Item] = []
    private(set) var selectedIndex = 0
    private var rowViews: [NSView] = []
    var onAccept: ((Int) -> Void)?

    private final class CandidateRowView: NSView {
        let title: String
        let detail: String
        let selected: Bool
        var onPress: (() -> Void)?

        init(title: String, detail: String, selected: Bool) {
            self.title = title
            self.detail = detail
            self.selected = selected
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { "\(title), \(detail)" }
        override func accessibilityValue() -> Any? { selected ? "Selected" : nil }
        override func accessibilityPerformPress() -> Bool { onPress?(); return true }
        override func mouseDown(with event: NSEvent) { onPress?() }
    }

    private static let maxVisibleRows = 8
    private static let rowHeight: CGFloat = 26

    var isVisible: Bool { window.isVisible }

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
        background.layer?.cornerRadius = DesignTokens.radiusMD
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = DesignTokens.borderWidth
        background.layer?.borderColor = DesignTokens.midnight.separator.cgColor

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
    func show(items: [Item], at screenPoint: NSPoint, parent: NSWindow) {
        self.candidates = items
        selectedIndex = 0
        rebuildRows()

        let size = outerStack.fittingSize
        window.setContentSize(NSSize(width: max(size.width, 310), height: size.height))
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
        rebuildRows()
    }

    private func rebuildRows() {
        rowViews.forEach { stackView.removeArrangedSubview($0); $0.removeFromSuperview() }
        rowViews.removeAll()
        let firstIndex = min(max(0, selectedIndex - Self.maxVisibleRows + 1), max(0, candidates.count - Self.maxVisibleRows))
        for index in firstIndex..<min(firstIndex + Self.maxVisibleRows, candidates.count) {
            let candidate = candidates[index]
            let row = CandidateRowView(title: candidate.title, detail: candidate.detail, selected: index == selectedIndex)
            row.onPress = { [weak self] in self?.onAccept?(index) }
            row.wantsLayer = true
            row.layer?.cornerRadius = 4
            row.layer?.backgroundColor = index == selectedIndex ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
            let title = NSTextField(labelWithString: candidate.title)
            title.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            title.textColor = index == selectedIndex ? .selectedMenuItemTextColor : .labelColor
            title.lineBreakMode = .byTruncatingMiddle
            let detail = NSTextField(labelWithString: candidate.detail)
            detail.font = .systemFont(ofSize: 10, weight: .medium)
            detail.textColor = index == selectedIndex ? .selectedMenuItemTextColor : .secondaryLabelColor
            for field in [title, detail] {
                field.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(field)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: Self.rowHeight),
                row.widthAnchor.constraint(equalToConstant: 290),
                title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 7),
                title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                title.trailingAnchor.constraint(lessThanOrEqualTo: detail.leadingAnchor, constant: -12),
                detail.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -7),
                detail.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])
            stackView.addArrangedSubview(row)
            rowViews.append(row)
        }
    }
}
