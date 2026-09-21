import AppKit
import Combine

@MainActor
final class SQLEditorViewController: NSViewController {
    private let appState: AppState
    private var appCancellables = Set<AnyCancellable>()
    private var documentCancellables = Set<AnyCancellable>()

    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let syntaxHighlighter = SQLSyntaxHighlighter()
    private let toolbar = NSView()

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindWorkspace()
    }

    private func setupUI() {
        runButton.bezelStyle = .rounded
        runButton.target = self
        runButton.action = #selector(run)
        runButton.keyEquivalent = "\r"
        runButton.keyEquivalentModifierMask = [.command]
        runButton.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = FontLibrary.sans(12, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.addSubview(titleLabel)
        toolbar.addSubview(progressIndicator)
        toolbar.addSubview(runButton)

        textView.isRichText = false
        textView.font = FontLibrary.mono(12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticTextCompletionEnabled = true
        textView.allowsUndo = true
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.delegate = syntaxHighlighter

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toolbar)
        view.addSubview(divider)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            runButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            runButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            progressIndicator.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -8),
            progressIndicator.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            divider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bindWorkspace() {
        appState.$activeDocumentID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.bindActiveDocument() }
            .store(in: &appCancellables)

        appState.connectionManager.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHeader() }
            .store(in: &appCancellables)

        appState.themeStore.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &appCancellables)

        applyTheme(appState.themeStore.current)

        appState.insertRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sql in self?.insertSnippet(sql) }
            .store(in: &appCancellables)

        bindActiveDocument()
    }

    private func insertSnippet(_ sql: String) {
        guard textView.isEditable else { return }
        textView.insertText(sql, replacementRange: textView.selectedRange())
        appState.updateActiveSQL(textView.string)
        applyHighlighting()
    }

    private func bindActiveDocument() {
        documentCancellables.removeAll()

        guard let state = appState.activeState else {
            textView.string = ""
            textView.isEditable = false
            updateHeader()
            return
        }

        textView.isEditable = true
        if textView.string != state.sql {
            textView.string = state.sql
            applyHighlighting()
        }

        state.$sql
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, self.textView.string != text else { return }
                self.textView.string = text
                self.applyHighlighting()
            }
            .store(in: &documentCancellables)

        state.$isExecuting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] executing in
                guard let self else { return }
                self.updateHeader()
                executing ? self.progressIndicator.startAnimation(nil) : self.progressIndicator.stopAnimation(nil)
            }
            .store(in: &documentCancellables)

        updateHeader()
    }

    private func updateHeader() {
        guard let document = appState.activeDocument, let state = appState.activeState else {
            titleLabel.stringValue = "No query open"
            runButton.isEnabled = false
            return
        }
        let connectionName = appState.selectedProfile?.name
        titleLabel.stringValue = connectionName.map { "\(document.name) — \($0)" } ?? document.name
        runButton.isEnabled = !state.isExecuting
    }

    @objc private func run() {
        appState.executeCurrentSQL()
    }

    private func applyHighlighting() {
        guard let textStorage = textView.textStorage else { return }
        syntaxHighlighter.highlight(textStorage)
    }

    private func applyTheme(_ theme: Theme) {
        toolbar.layer?.backgroundColor = theme.barFillPaint.cgColor
        toolbar.layer?.borderColor = theme.barBorder.cgColor
        toolbar.layer?.borderWidth = 1
    }
}

extension SQLEditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        appState.updateActiveSQL(textView.string)
    }

    func textView(
        _ textView: NSTextView,
        completions words: [String],
        forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String] {
        let partial = (textView.string as NSString).substring(with: charRange).lowercased()
        guard !partial.isEmpty else { return [] }
        return SQLSyntaxHighlighter.keywords
            .filter { $0.hasPrefix(partial) }
            .sorted()
            .map { $0.uppercased() }
    }
}
