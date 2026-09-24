import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class ResultsGridViewController: NSViewController {
    private let appState: AppState
    private var appCancellables = Set<AnyCancellable>()
    private var documentCancellables = Set<AnyCancellable>()
    private var result: QueryResult = .empty

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "Copy Results", target: nil, action: nil)
    private let exportCSVButton = NSButton(title: "Export CSV", target: nil, action: nil)
    private let exportJSONButton = NSButton(title: "Export JSON", target: nil, action: nil)
    private let pageButtonsStack = NSStackView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let statusBar = NSView()

    /// Local mirrors of the active document's pagination state — kept in
    /// sync via the Combine subscriptions in bindActiveDocument, read
    /// together by updatePagingUI() since page buttons depend on all of
    /// them at once (current page, total, and whether a fetch is in
    /// flight) and Combine only hands you one changed value at a time.
    private var isPaginated = false
    private var currentPage = 0
    private var totalRowCount: Int?
    private var isExecuting = false

    /// Inline cell editing state — see refreshPrimaryKeyIfNeeded(). Both
    /// nil/empty means "not editable," the state every result starts in;
    /// a real primary key has to be confirmed before any cell allows
    /// editing at all.
    private var editableTable: String?
    private var primaryKeyColumnNames: [String] = []
    private var primaryKeyFetchKey: String?

    /// Foreign keys on the current single-source table, keyed by local
    /// column name — powers ⌥-click-to-navigate. Independent of
    /// primaryKeyColumnNames: navigating doesn't need a primary key on
    /// this table, only on knowing which table a column belongs to
    /// (same editableTable gate cell editing already uses).
    private var foreignKeysByColumn: [String: ForeignKeyReference] = [:]
    private var foreignKeyFetchKey: String?

    /// Editing is only actually safe once the primary key columns are
    /// both known AND present in the current result set — a SELECT that
    /// leaves out the key column (e.g. `SELECT name FROM users`) can't be
    /// scoped to one row no matter how confidently the table itself was
    /// identified.
    private var canEditCurrentResult: Bool {
        !primaryKeyColumnNames.isEmpty && primaryKeyColumnNames.allSatisfy { result.columns.contains($0) }
    }

    /// Above this many pages, individual page-number buttons give way to
    /// a plain "Page X of Y" readout — otherwise a huge table's page bar
    /// would just keep growing forever.
    private static let maxPageButtons = 10

    /// Cell font for the grid — previously a hardcoded FontLibrary.mono(11)
    /// that ignored the Preferences font-size setting entirely, the one
    /// place in the app where changing it had no visible effect. Now
    /// tracks appState.fontPreferences the same way the SQL/snippet
    /// editors already did.
    private var dataFont: NSFont = FontLibrary.mono(11)

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
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 20
        tableView.target = self
        tableView.action = #selector(handleClick)

        let menu = NSMenu()
        menu.addItem(withTitle: "Copy Cell", action: #selector(copySelectedCell), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Row", action: #selector(copySelectedRow), keyEquivalent: "")
        tableView.menu = menu

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        copyButton.target = self
        copyButton.action = #selector(copyAll)
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        exportCSVButton.target = self
        exportCSVButton.action = #selector(exportCSV)
        exportCSVButton.bezelStyle = .rounded
        exportCSVButton.translatesAutoresizingMaskIntoConstraints = false

        exportJSONButton.target = self
        exportJSONButton.action = #selector(exportJSON)
        exportJSONButton.bezelStyle = .rounded
        exportJSONButton.translatesAutoresizingMaskIntoConstraints = false

        pageButtonsStack.orientation = .horizontal
        pageButtonsStack.spacing = 4
        pageButtonsStack.isHidden = true
        pageButtonsStack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = FontLibrary.sans(11)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.isHidden = true
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.wantsLayer = true
        statusBar.addSubview(statusLabel)
        statusBar.addSubview(copyButton)
        statusBar.addSubview(exportCSVButton)
        statusBar.addSubview(exportJSONButton)
        statusBar.addSubview(pageButtonsStack)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusBar)
        view.addSubview(divider)
        view.addSubview(scrollView)
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 26),

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 10),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -10),
            copyButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            exportCSVButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            exportCSVButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            exportJSONButton.trailingAnchor.constraint(equalTo: exportCSVButton.leadingAnchor, constant: -8),
            exportJSONButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            pageButtonsStack.trailingAnchor.constraint(equalTo: exportJSONButton.leadingAnchor, constant: -8),
            pageButtonsStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            divider.topAnchor.constraint(equalTo: statusBar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -40)
        ])
    }

    private func bindWorkspace() {
        appState.$activeDocumentID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.bindActiveDocument() }
            .store(in: &appCancellables)

        appState.themeStore.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &appCancellables)

        Publishers.CombineLatest(appState.fontPreferences.$choice, appState.fontPreferences.$size)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.applyFont() }
            .store(in: &appCancellables)

        applyTheme(appState.themeStore.current)
        applyFont()
        bindActiveDocument()
    }

    private func applyFont() {
        dataFont = appState.fontPreferences.font
        tableView.rowHeight = max(20, dataFont.pointSize + 8)
        tableView.reloadData()
    }

    private func applyTheme(_ theme: Theme) {
        statusBar.layer?.backgroundColor = theme.barFillPaint.cgColor
        statusBar.layer?.borderColor = theme.barBorder.cgColor
        statusBar.layer?.borderWidth = 1
    }

    private func bindActiveDocument() {
        documentCancellables.removeAll()
        editableTable = nil
        primaryKeyColumnNames = []
        primaryKeyFetchKey = nil
        foreignKeysByColumn = [:]
        foreignKeyFetchKey = nil

        guard let state = appState.activeState else {
            apply(.empty)
            return
        }

        state.$queryResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in self?.apply(result) }
            .store(in: &documentCancellables)

        state.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in self?.applyError(error) }
            .store(in: &documentCancellables)

        state.$paginationBaseSQL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] base in
                self?.isPaginated = base != nil
                self?.updatePagingUI()
            }
            .store(in: &documentCancellables)

        state.$currentPage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] page in
                self?.currentPage = page
                self?.updatePagingUI()
            }
            .store(in: &documentCancellables)

        state.$totalRowCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] total in
                self?.totalRowCount = total
                self?.updatePagingUI()
            }
            .store(in: &documentCancellables)

        state.$isExecuting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] executing in
                self?.isExecuting = executing
                self?.updatePagingUI()
            }
            .store(in: &documentCancellables)

        state.$editableTable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] table in
                self?.editableTable = table
                self?.refreshPrimaryKeyIfNeeded()
                self?.refreshForeignKeysIfNeeded()
            }
            .store(in: &documentCancellables)
    }

    /// Fetches this table's foreign keys once per (connection, table),
    /// same caching shape as refreshPrimaryKeyIfNeeded. Doesn't gate on a
    /// primary key existing — navigating away from a FK cell doesn't
    /// need one on the table being navigated from.
    private func refreshForeignKeysIfNeeded() {
        guard let table = editableTable,
              let profile = appState.selectedProfile,
              let connection = appState.connectionManager.connection(for: profile.id) else {
            foreignKeysByColumn = [:]
            foreignKeyFetchKey = nil
            return
        }
        let key = "\(profile.id)|\(table)"
        guard foreignKeyFetchKey != key else { return }
        foreignKeyFetchKey = key
        foreignKeysByColumn = [:]
        Task {
            let database = appState.connectionManager.currentDatabases[profile.id] ?? profile.database
            let foreignKeys = (try? await connection.foreignKeys(table: table, inDatabase: database)) ?? []
            guard self.editableTable == table else { return }
            self.foreignKeysByColumn = Dictionary(uniqueKeysWithValues: foreignKeys.map { ($0.column, $0) })
            self.tableView.reloadData()
            self.updatePagingUI()
        }
    }

    /// Fetches the primary key once per (connection, table) — not on
    /// every keystroke or page turn, this only needs to run again when
    /// the editable table itself changes. Empty/no primary key means
    /// editing stays off for this result (see canEditCurrentResult).
    private func refreshPrimaryKeyIfNeeded() {
        guard let table = editableTable,
              let profile = appState.selectedProfile,
              let connection = appState.connectionManager.connection(for: profile.id) else {
            primaryKeyColumnNames = []
            primaryKeyFetchKey = nil
            tableView.reloadData()
            return
        }
        let key = "\(profile.id)|\(table)"
        guard primaryKeyFetchKey != key else { return }
        primaryKeyFetchKey = key
        primaryKeyColumnNames = []
        Task {
            let database = appState.connectionManager.currentDatabases[profile.id] ?? profile.database
            let columns = (try? await connection.primaryKeyColumns(table: table, inDatabase: database)) ?? []
            guard self.editableTable == table else { return }
            self.primaryKeyColumnNames = columns
            self.tableView.reloadData()
        }
    }

    private func apply(_ result: QueryResult) {
        self.result = result
        rebuildColumns()
        tableView.reloadData()
        copyButton.isEnabled = !result.rows.isEmpty
        exportCSVButton.isEnabled = !result.rows.isEmpty
        exportJSONButton.isEnabled = !result.rows.isEmpty

        if result.columns.isEmpty {
            messageLabel.stringValue = result.affectedRows.map { "\($0) row(s) affected" } ?? "No results"
            messageLabel.textColor = .secondaryLabelColor
            messageLabel.isHidden = false
            scrollView.isHidden = true
        } else {
            messageLabel.isHidden = true
            scrollView.isHidden = false
        }
        updatePagingUI()
    }

    private func applyError(_ error: String?) {
        guard let error else { return }
        messageLabel.stringValue = error
        messageLabel.textColor = .systemRed
        messageLabel.isHidden = false
        scrollView.isHidden = true
        statusLabel.stringValue = ""
    }

    /// Single source of truth for both the status label and the page
    /// button row — both depend on the same combination of state
    /// (row count, pagination on/off, current page, total, in-flight),
    /// so this is called from every publisher that touches any of them
    /// rather than splitting the logic across each individual sink.
    /// Appended to the row-count label whenever the current result has at
    /// least one foreign-key column — the blue cell color alone wasn't
    /// discoverable enough (a real user saw the blue text and still didn't
    /// know Option-click was the gesture), so this spells it out in the
    /// one status-bar label that's always on screen instead of relying on
    /// a hover tooltip nobody's guaranteed to find.
    /// Sets the row-count label, appending the FK hint (bundled Icons8
    /// link glyph, tinted to match the label's own color — a template
    /// NSImage dropped into an NSAttributedString via NSTextAttachment
    /// draws as flat black otherwise, invisible against this app's
    /// fixed-dark chrome) whenever the current result has at least one
    /// foreign-key column. Spelled out in the one status-bar label
    /// that's always on screen, not just a hover tooltip — the blue cell
    /// color alone wasn't discoverable enough on its own.
    private func setStatusText(_ base: String) {
        guard !foreignKeysByColumn.isEmpty else {
            statusLabel.stringValue = base
            return
        }
        let font = statusLabel.font ?? FontLibrary.sans(11)
        let color = NSColor.secondaryLabelColor
        let text = NSMutableAttributedString(
            string: base + "  ",
            attributes: [.font: font, .foregroundColor: color]
        )
        let attachment = NSTextAttachment()
        attachment.image = Self.tinted(AppIcon.link.image, color: color)
        attachment.bounds = CGRect(x: 0, y: -1.5, width: 11, height: 11)
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(
            string: " ⌥-click a blue cell to follow its foreign key",
            attributes: [.font: font, .foregroundColor: color]
        ))
        statusLabel.attributedStringValue = text
    }

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }

    private func updatePagingUI() {
        guard isPaginated else {
            setStatusText("\(result.rows.count) row(s)")
            pageButtonsStack.isHidden = true
            return
        }
        guard let total = totalRowCount else {
            setStatusText("\(result.rows.count) row(s) — counting total…")
            pageButtonsStack.isHidden = true
            return
        }
        // "1-100 of 10000" reads better than "Page 1 of 100" — tells you
        // exactly which rows you're looking at, not just a page ordinal.
        let startRow = currentPage * AppState.resultPageSize + 1
        let endRow = result.rows.isEmpty ? startRow : startRow + result.rows.count - 1
        setStatusText("\(startRow)-\(endRow) of \(total)")
        let totalPages = max(1, Int(ceil(Double(total) / Double(AppState.resultPageSize))))
        pageButtonsStack.isHidden = totalPages <= 1
        rebuildPageButtons(totalPages: totalPages)
    }

    private func rebuildPageButtons(totalPages: Int) {
        pageButtonsStack.arrangedSubviews.forEach {
            pageButtonsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard totalPages > 1 else { return }

        let prev = NSButton(title: "‹", target: self, action: #selector(goToPrevPage))
        prev.bezelStyle = .rounded
        prev.isEnabled = currentPage > 0 && !isExecuting
        pageButtonsStack.addArrangedSubview(prev)

        if totalPages <= Self.maxPageButtons {
            for page in 0..<totalPages {
                let button = NSButton(title: "\(page + 1)", target: self, action: #selector(goToPageButtonTapped(_:)))
                button.tag = page
                button.bezelStyle = .rounded
                button.contentTintColor = page == currentPage ? .controlAccentColor : nil
                button.isEnabled = !isExecuting
                pageButtonsStack.addArrangedSubview(button)
            }
        }
        // Above maxPageButtons, just Prev/Next — statusLabel's "1-100 of
        // 10000" already says exactly where you are, a second "Page X of
        // Y" readout here would just be a worse, redundant restatement.

        let next = NSButton(title: "›", target: self, action: #selector(goToNextPage))
        next.bezelStyle = .rounded
        next.isEnabled = currentPage < totalPages - 1 && !isExecuting
        pageButtonsStack.addArrangedSubview(next)
    }

    private func rebuildColumns() {
        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }
        for (index, name) in result.columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(index)"))
            column.title = name
            column.width = 140
            column.minWidth = 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: "col\(index)", ascending: true)
            tableView.addTableColumn(column)
        }
    }

    @objc private func goToPageButtonTapped(_ sender: NSButton) {
        appState.goToPage(sender.tag)
    }

    @objc private func goToPrevPage() {
        appState.goToPage(max(0, currentPage - 1))
    }

    @objc private func goToNextPage() {
        appState.goToPage(currentPage + 1)
    }

    @objc private func copyAll() {
        var lines = [result.columns.joined(separator: "\t")]
        lines += result.rows.map(rowText)
        copyToPasteboard(lines.joined(separator: "\n"))
    }

    @objc private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "results.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            try? self.csvText().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func csvText() -> String {
        var lines = [result.columns.map(csvField).joined(separator: ",")]
        lines += result.rows.map { row in row.map { csvField($0.displayString) }.joined(separator: ",") }
        return lines.joined(separator: "\r\n")
    }

    @objc private func exportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "results.json"
        panel.allowedContentTypes = [.json]
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            try? self.jsonData().write(to: url)
        }
    }

    /// Every value comes through as QueryValue (.text or .null) with no
    /// numeric/bool distinction preserved at this layer — same tradeoff
    /// CSV export makes — so every non-null value is a JSON string, not a
    /// number, even for numeric columns.
    private func jsonData() -> Data {
        let objects: [[String: Any]] = result.rows.map { row in
            var object: [String: Any] = [:]
            for (index, column) in result.columns.enumerated() where index < row.count {
                object[column] = row[index].isNull ? NSNull() : row[index].displayString
            }
            return object
        }
        return (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted])) ?? Data("[]".utf8)
    }

    /// RFC 4180: quote a field only if it needs it (contains the
    /// delimiter, a quote, or a newline), doubling any embedded quotes.
    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// ⌥-click on a foreign-key cell jumps to its referenced row. Plain
    /// clicks (and ⌘-click, which NSTableView already uses for multi-row
    /// selection) fall through and do nothing extra here — this only acts
    /// when Option is held, so it never competes with normal selection.
    @objc private func handleClick() {
        guard NSEvent.modifierFlags.contains(.option) else { return }
        let row = tableView.clickedRow
        let column = tableView.clickedColumn
        guard row >= 0, row < result.rows.count,
              column >= 0, column < result.columns.count, column < result.rows[row].count,
              let reference = foreignKeysByColumn[result.columns[column]] else { return }
        let value = result.rows[row][column]
        guard !value.isNull else { return }
        appState.navigateForeignKey(reference, value: value)
    }

    @objc private func copySelectedCell() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        let column = tableView.clickedColumn >= 0 ? tableView.clickedColumn : tableView.selectedColumn
        guard row >= 0, column >= 0, row < result.rows.count, column < result.rows[row].count else { return }
        copyToPasteboard(result.rows[row][column].displayString)
    }

    @objc private func copySelectedRow() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < result.rows.count else { return }
        copyToPasteboard(rowText(result.rows[row]))
    }

    private func rowText(_ row: [QueryValue]) -> String {
        row.map(\.displayString).joined(separator: "\t")
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension ResultsGridViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        result.rows.count
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let index = Int(key.dropFirst(3)) else { return }
        result = QueryResult(
            columns: result.columns,
            rows: result.rows.sorted { lhs, rhs in
                let ascending = descriptor.ascending
                let left = lhs[index].displayString
                let right = rhs[index].displayString
                return ascending ? left < right : left > right
            },
            affectedRows: result.affectedRows
        )
        tableView.reloadData()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn,
              let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn),
              row < result.rows.count, columnIndex < result.rows[row].count else { return nil }
        let value = result.rows[row][columnIndex]

        let identifier = NSUserInterfaceItemIdentifier("Cell")
        let cell: NSTableCellView
        let textField: NSTextField

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
           let reusedText = reused.textField {
            cell = reused
            textField = reusedText
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.delegate = self
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        // Set on every call, not just at creation — a reused cell would
        // otherwise keep whatever font it was first built with even after
        // the size preference changes.
        let reference = foreignKeysByColumn[result.columns[columnIndex]]
        textField.font = dataFont
        textField.stringValue = value.displayString
        textField.textColor = value.isNull ? .tertiaryLabelColor : (reference != nil ? .linkColor : .labelColor)
        textField.isEditable = canEditCurrentResult
        if let reference, !value.isNull {
            cell.toolTip = "\(value.displayString) — ⌥-click to view in \(reference.referencedTable)"
        } else {
            cell.toolTip = value.displayString
        }
        return cell
    }
}

extension ResultsGridViewController: NSTextFieldDelegate {
    /// Commits an inline cell edit as a real UPDATE, scoped to the row's
    /// primary key. The field is immediately reverted to its pre-edit
    /// text rather than optimistically kept — appState.updateCell only
    /// refreshes the grid on a *confirmed* write (after Touch ID and a
    /// successful UPDATE), so this avoids ever showing a value that
    /// wasn't actually saved (auth cancelled, the write failed, etc.)
    /// without needing separate rollback logic for that case.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let control = obj.object as? NSTextField else { return }
        let row = tableView.row(for: control)
        let column = tableView.column(for: control)
        guard canEditCurrentResult, let table = editableTable,
              row >= 0, row < result.rows.count,
              column >= 0, column < result.columns.count,
              column < result.rows[row].count else { return }

        let oldValue = result.rows[row][column]
        // The grid already renders NULL cells as the literal text "NULL"
        // (see the textColor/tertiaryLabelColor line above) — typing that
        // same literal back is how you set a cell to NULL, consistent
        // with how it's already displayed rather than a separate control.
        let newText = control.stringValue
        let newValue: QueryValue = newText == "NULL" ? .null : .text(newText)
        control.stringValue = oldValue.displayString
        guard newValue != oldValue else { return }

        var whereColumns: [String] = []
        var whereValues: [QueryValue] = []
        for pkColumn in primaryKeyColumnNames {
            guard let pkIndex = result.columns.firstIndex(of: pkColumn) else { return }
            whereColumns.append(pkColumn)
            whereValues.append(result.rows[row][pkIndex])
        }

        appState.updateCell(
            table: table,
            setColumn: result.columns[column],
            oldValue: oldValue,
            newValue: newValue,
            whereColumns: whereColumns,
            whereValues: whereValues
        )
    }
}
