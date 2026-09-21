import AppKit
import Combine

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
    private let loadMoreButton = NSButton(title: "Load More", target: nil, action: nil)
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let statusBar = NSView()

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

        loadMoreButton.target = self
        loadMoreButton.action = #selector(loadMore)
        loadMoreButton.bezelStyle = .rounded
        loadMoreButton.isHidden = true
        loadMoreButton.translatesAutoresizingMaskIntoConstraints = false

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
        statusBar.addSubview(loadMoreButton)

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

            loadMoreButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            loadMoreButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

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

        applyTheme(appState.themeStore.current)
        bindActiveDocument()
    }

    private func applyTheme(_ theme: Theme) {
        statusBar.layer?.backgroundColor = theme.barFillPaint.cgColor
        statusBar.layer?.borderColor = theme.barBorder.cgColor
        statusBar.layer?.borderWidth = 1
    }

    private func bindActiveDocument() {
        documentCancellables.removeAll()

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

        Publishers.CombineLatest(state.$hasMorePages, state.$isExecuting)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasMore, executing in
                self?.loadMoreButton.isHidden = !hasMore
                self?.loadMoreButton.isEnabled = !executing
            }
            .store(in: &documentCancellables)
    }

    private func apply(_ result: QueryResult) {
        self.result = result
        rebuildColumns()
        tableView.reloadData()
        copyButton.isEnabled = !result.rows.isEmpty

        if result.columns.isEmpty {
            messageLabel.stringValue = result.affectedRows.map { "\($0) row(s) affected" } ?? "No results"
            messageLabel.textColor = .secondaryLabelColor
            messageLabel.isHidden = false
            scrollView.isHidden = true
        } else {
            messageLabel.isHidden = true
            scrollView.isHidden = false
        }
        statusLabel.stringValue = "\(result.rows.count) row(s)"
    }

    private func applyError(_ error: String?) {
        guard let error else { return }
        messageLabel.stringValue = error
        messageLabel.textColor = .systemRed
        messageLabel.isHidden = false
        scrollView.isHidden = true
        statusLabel.stringValue = ""
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

    @objc private func loadMore() {
        appState.loadMoreRows()
    }

    @objc private func copyAll() {
        var lines = [result.columns.joined(separator: "\t")]
        lines += result.rows.map(rowText)
        copyToPasteboard(lines.joined(separator: "\n"))
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
            textField.font = FontLibrary.mono(11)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        textField.stringValue = value.displayString
        textField.textColor = value.isNull ? .tertiaryLabelColor : .labelColor
        cell.toolTip = value.displayString
        return cell
    }
}
