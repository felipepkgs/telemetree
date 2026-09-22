import AppKit
import Combine

@MainActor
final class QueryHistoryWindowController: NSWindowController {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var filteredEntries: [QueryHistoryEntry] = []
    private var searchText: String = "" {
        didSet { refilter() }
    }

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Query History"
        window.minSize = NSSize(width: 420, height: 240)
        window.isRestorable = false
        window.center()
        super.init(window: window)
        buildUI()
        bind()
        refilter()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        searchField.placeholderString = "Search history"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 20
        tableView.target = self
        tableView.doubleAction = #selector(reopenSelected)

        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = ""
        statusColumn.width = 24
        tableView.addTableColumn(statusColumn)

        let sqlColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sql"))
        sqlColumn.title = "SQL"
        sqlColumn.width = 340
        tableView.addTableColumn(sqlColumn)

        let connectionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("connection"))
        connectionColumn.title = "Connection"
        connectionColumn.width = 120
        tableView.addTableColumn(connectionColumn)

        let timeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        timeColumn.title = "Time"
        timeColumn.width = 130
        tableView.addTableColumn(timeColumn)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        let clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistory))
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "Double-click to reopen")
        hint.font = FontLibrary.sans(11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(clearButton)
        contentView.addSubview(hint)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -8),

            hint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            hint.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func bind() {
        appState.historyStore.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refilter() }
            .store(in: &cancellables)

        Publishers.CombineLatest(appState.fontPreferences.$choice, appState.fontPreferences.$size)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    private func refilter() {
        let all = appState.historyStore.entries
        if searchText.isEmpty {
            filteredEntries = all
        } else {
            filteredEntries = all.filter {
                $0.sql.localizedCaseInsensitiveContains(searchText) ||
                $0.connectionName.localizedCaseInsensitiveContains(searchText)
            }
        }
        tableView.reloadData()
    }

    @objc private func clearHistory() {
        appState.historyStore.clear()
    }

    @objc private func reopenSelected() {
        let row = tableView.clickedRow
        guard row >= 0, row < filteredEntries.count else { return }
        appState.reopenHistoryEntry(filteredEntries[row])
    }
}

extension QueryHistoryWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === searchField else { return }
        searchText = field.stringValue
    }
}

extension QueryHistoryWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredEntries.count, let column = tableColumn else { return nil }
        let entry = filteredEntries[row]

        let cell: NSTableCellView
        let textField: NSTextField
        if let reused = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView,
           let reusedText = reused.textField {
            cell = reused
            textField = reusedText
        } else {
            cell = NSTableCellView()
            cell.identifier = column.identifier
            textField = NSTextField(labelWithString: "")
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

        switch column.identifier.rawValue {
        case "status":
            textField.font = FontLibrary.sans(11)
            textField.stringValue = entry.succeeded ? "✓" : "✕"
            textField.textColor = entry.succeeded ? .systemGreen : .systemRed
        case "sql":
            textField.font = appState.fontPreferences.font
            textField.stringValue = entry.sql.replacingOccurrences(of: "\n", with: " ")
            textField.textColor = .labelColor
        case "connection":
            textField.font = FontLibrary.sans(11)
            textField.stringValue = entry.connectionName
            textField.textColor = .secondaryLabelColor
        case "time":
            textField.font = FontLibrary.sans(11)
            textField.stringValue = Self.timeFormatter.string(from: entry.timestamp)
            textField.textColor = .secondaryLabelColor
        default:
            break
        }
        return cell
    }
}
