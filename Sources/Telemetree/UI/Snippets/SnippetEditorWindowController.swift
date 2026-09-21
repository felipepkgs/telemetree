import AppKit

/// The one thing that was missing from the snippet library: an actual way
/// to put SQL into a snippet. Selecting a snippet in the sidebar inserts
/// it into the active editor; this window is how you edit its content —
/// opened via double-click or the "Edit…" context menu item.
@MainActor
final class SnippetEditorWindowController: NSWindowController {
    private let appState: AppState
    private let snippetID: UUID
    private let textView = NSTextView()
    private let syntaxHighlighter = SQLSyntaxHighlighter()

    init(appState: AppState, snippetID: UUID) {
        self.appState = appState
        self.snippetID = snippetID
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appState.snippetStore.snippet(id: snippetID)?.name ?? "Snippet"
        window.minSize = NSSize(width: 360, height: 240)
        window.isRestorable = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        textView.isRichText = false
        textView.font = FontLibrary.mono(12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.delegate = syntaxHighlighter
        textView.string = appState.snippetStore.snippet(id: snippetID)?.sql ?? ""

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -12),

            doneButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            doneButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        if let textStorage = textView.textStorage {
            syntaxHighlighter.highlight(textStorage)
        }
    }

    @objc private func closeWindow() {
        window?.close()
    }
}

extension SnippetEditorWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        appState.snippetStore.updateSQL(snippetID, sql: textView.string)
    }
}
