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
    private var isHandlingTextChange = false

    // MARK: - Completion
    private lazy var completionController = SQLCompletionController(textView: textView)

    // MARK: - Schema completion cache
    //
    // Table names are fetched once per (connection, current database) —
    // not per keystroke, completion has to return synchronously, so this
    // is kept warm ahead of time via the Combine subscriptions in
    // bindWorkspace/bindActiveDocument. Keyed on the connection's current
    // database (connectionManager.currentDatabases, set by
    // AppState.selectDatabase when the sidebar's last-clicked database
    // changes it via USE), not the profile's originally-configured one —
    // otherwise completion would keep suggesting tables from a database
    // you've since switched away from.
    private var cachedTableNames: [String] = []
    private var cachedTablesKey: String?

    // Column names are fetched per table, on demand — unlike table names,
    // there's no fixed small set to warm ahead of time, so this fills in
    // lazily as completion actually asks about a table (see
    // columnNamesProvider below), keyed by lowercased table name.
    private var cachedColumnsByTable: [String: [String]] = [:]
    private var pendingColumnFetches: Set<String> = []

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
        completionController.tableNamesProvider = { [weak self] in self?.cachedTableNames ?? [] }
        completionController.columnNamesProvider = { [weak self] tables in self?.columnNames(for: tables) ?? [] }
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
        textView.font = appState.fontPreferences.font
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        // Deliberately off: this is macOS's own system-wide predictive-text
        // engine, not scoped to SQL keywords — it suggested on field/table
        // names too, and running alongside AppKit's own complete(_:)
        // machinery (formerly used here) was the root cause of a
        // reentrancy stack-overflow crash (felipepkgs/telemetree#4). The
        // editor now drives its own completion popup (see the
        // NSTextViewDelegate extension below) instead of complete(_:), but
        // this stays off regardless — still not SQL-scoped.
        textView.isAutomaticTextCompletionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
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

        appState.connectionManager.$connectedIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTableNamesIfNeeded() }
            .store(in: &appCancellables)

        appState.connectionManager.$currentDatabases
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTableNamesIfNeeded() }
            .store(in: &appCancellables)

        applyTheme(appState.themeStore.current)

        Publishers.CombineLatest(appState.fontPreferences.$choice, appState.fontPreferences.$size)
            .combineLatest(appState.syntaxThemeStore.$current)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, syntaxTheme in self?.applyFontAndSyntaxTheme(syntaxTheme) }
            .store(in: &appCancellables)

        applyFontAndSyntaxTheme(appState.syntaxThemeStore.current)

        appState.insertRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sql in self?.insertSnippet(sql) }
            .store(in: &appCancellables)

        bindActiveDocument()
    }

    private func applyFontAndSyntaxTheme(_ syntaxTheme: SyntaxTheme) {
        let font = appState.fontPreferences.font
        textView.font = font
        syntaxHighlighter.font = font
        syntaxHighlighter.theme = syntaxTheme
        applyHighlighting()
    }

    private func insertSnippet(_ sql: String) {
        guard textView.isEditable else { return }
        textView.insertText(sql, replacementRange: textView.selectedRange())
        appState.updateActiveSQL(textView.string)
        applyHighlighting()
    }

    private func bindActiveDocument() {
        documentCancellables.removeAll()
        completionController.hide()

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

        state.$connectionProfileID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTableNamesIfNeeded() }
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

    private func refreshTableNamesIfNeeded() {
        guard let profile = appState.selectedProfile,
              let connection = appState.connectionManager.connection(for: profile.id) else { return }
        let database = appState.connectionManager.currentDatabases[profile.id] ?? profile.database
        let key = "\(profile.id)|\(database)"
        guard cachedTablesKey != key else { return }
        cachedTablesKey = key
        // Column names are scoped to a specific table within a specific
        // database — once the database changes, anything cached under the
        // old one is stale (a same-named table there could have different
        // columns, or not exist at all).
        cachedColumnsByTable.removeAll()
        Task {
            let tables = (try? await connection.listTables(inDatabase: database))?.map(\.name) ?? []
            guard appState.selectedProfile?.id == profile.id,
                  (appState.connectionManager.currentDatabases[profile.id] ?? profile.database) == database else { return }
            cachedTableNames = tables
        }
    }

    /// Synchronous by necessity (completion has to return immediately) —
    /// returns whatever's already cached and kicks off a fetch in the
    /// background for any table that isn't, so the next keystroke picks
    /// it up. `tables` is a best-effort list of table names referenced by
    /// the statement under the caret (see SQLCompletionController).
    private func columnNames(for tables: [String]) -> [String] {
        var results: [String] = []
        for table in tables {
            let key = table.lowercased()
            if let cached = cachedColumnsByTable[key] {
                results.append(contentsOf: cached)
            } else {
                fetchColumnsIfNeeded(table: table)
            }
        }
        return results
    }

    private func fetchColumnsIfNeeded(table: String) {
        let key = table.lowercased()
        guard !pendingColumnFetches.contains(key),
              let profile = appState.selectedProfile,
              let connection = appState.connectionManager.connection(for: profile.id) else { return }
        let database = appState.connectionManager.currentDatabases[profile.id] ?? profile.database
        pendingColumnFetches.insert(key)
        Task {
            defer { pendingColumnFetches.remove(key) }
            let columns = (try? await connection.listColumns(table: table, inDatabase: database)) ?? []
            guard appState.selectedProfile?.id == profile.id,
                  (appState.connectionManager.currentDatabases[profile.id] ?? profile.database) == database else { return }
            cachedColumnsByTable[key] = columns
            // The popup may still be open waiting on exactly this table's
            // columns — recompute now that they've arrived instead of
            // making the user retype a character to see them.
            completionController.textDidChange()
        }
    }

    @objc private func run() {
        appState.executeCurrentSQL(currentExecutionTarget())
    }

    /// What Run/⌘Return actually sends: the real selection if there is
    /// one, otherwise just the statement the caret is currently inside —
    /// never the whole buffer. A document can hold more than one
    /// statement, and blindly running everything risked firing an
    /// unrelated (possibly destructive) statement sitting elsewhere in
    /// the same document.
    private func currentExecutionTarget() -> String {
        let selection = textView.selectedRange()
        if selection.length > 0 {
            return (textView.string as NSString).substring(with: selection)
        }
        if let statement = SQLStatementLocator.statement(containing: selection.location, in: textView.string) {
            return statement.text
        }
        return textView.string
    }

    private func applyHighlighting() {
        guard let textStorage = textView.textStorage else { return }
        syntaxHighlighter.highlight(textStorage)
        updateStatementHighlight()
    }

    /// Shows which statement Run would send by tinting its background —
    /// only when the caret has no active selection, since a real
    /// selection already reads clearly via the system's own selection
    /// color and already IS what Run would send.
    private static let statementHighlightColor = NSColor.systemGreen.withAlphaComponent(0.16)

    private func updateStatementHighlight() {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.removeAttribute(.backgroundColor, range: fullRange)

        let selection = textView.selectedRange()
        guard selection.length == 0,
              let statement = SQLStatementLocator.statement(containing: selection.location, in: textView.string),
              statement.range.length > 0,
              NSMaxRange(statement.range) <= textStorage.length else { return }
        // statement.range starts right after the previous statement's ";"
        // (Run/the caret-boundary lookup need that, to claim the gap
        // between statements) — but that means it can include leading
        // whitespace/newlines before the statement's actual first
        // character, which shouldn't be part of what's visibly painted.
        let text = textView.string as NSString
        let highlightRange = Self.trimmingLeadingWhitespace(statement.range, in: text)
        guard highlightRange.length > 0 else { return }
        textStorage.addAttribute(.backgroundColor, value: Self.statementHighlightColor, range: highlightRange)
    }

    private static func trimmingLeadingWhitespace(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        let end = NSMaxRange(range)
        while start < end, text.substring(with: NSRange(location: start, length: 1))
            .rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            start += 1
        }
        return NSRange(location: start, length: end - start)
    }

    private func applyTheme(_ theme: Theme) {
        toolbar.layer?.backgroundColor = theme.barFillPaint.cgColor
        toolbar.layer?.borderColor = theme.barBorder.cgColor
        toolbar.layer?.borderWidth = 1
    }
}

extension SQLEditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !isHandlingTextChange else { return }
        isHandlingTextChange = true
        defer { isHandlingTextChange = false }

        appState.updateActiveSQL(textView.string)
        completionController.textDidChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateStatementHighlight()
        completionController.selectionDidChange()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        completionController.doCommandBy(commandSelector)
    }
}
