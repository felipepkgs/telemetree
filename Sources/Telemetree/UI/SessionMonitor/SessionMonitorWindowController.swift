import AppKit

/// Read-only view of a server's currently active sessions/queries —
/// MySQL's SHOW FULL PROCESSLIST, Postgres's pg_stat_activity — auto-
/// refreshing while the window is open. Not offered for SQLite (see
/// DatabaseConnection.activeSessions()'s doc comment); the sidebar gates
/// this controller from ever being created for a SQLite connection.
@MainActor
final class SessionMonitorWindowController: NSWindowController {
    private let appState: AppState
    private let profile: ConnectionProfile
    private var result: QueryResult = .empty
    private var refreshTimer: Timer?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")

    private static let refreshInterval: TimeInterval = 2.5

    init(appState: AppState, profile: ConnectionProfile) {
        self.appState = appState
        self.profile = profile
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Active Sessions — \(profile.name)"
        window.minSize = NSSize(width: 420, height: 240)
        window.isRestorable = false
        window.center()
        super.init(window: window)
        buildUI()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 20
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        statusLabel.font = FontLibrary.sans(11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "Refresh Now", target: self, action: #selector(refreshNow))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(statusLabel)
        contentView.addSubview(refreshButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            refreshButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startAutoRefresh()
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        Task { await refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    @objc private func windowWillClose() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func refreshNow() {
        Task { await refresh() }
    }

    private func refresh() async {
        if !appState.connectionManager.connectedIDs.contains(profile.id) {
            await appState.connectionManager.connect(profile)
        }
        guard let connection = appState.connectionManager.connection(for: profile.id) else {
            statusLabel.stringValue = appState.connectionManager.connectionErrors[profile.id] ?? "Not connected"
            return
        }
        do {
            result = try await connection.activeSessions()
            rebuildColumns()
            tableView.reloadData()
            statusLabel.stringValue = "\(result.rows.count) active session(s) — updated \(Self.timeFormatter.string(from: Date()))"
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func rebuildColumns() {
        guard tableView.tableColumns.map(\.title) != result.columns else { return }
        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }
        for (index, name) in result.columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(index)"))
            column.title = name
            column.width = 120
            column.minWidth = 50
            tableView.addTableColumn(column)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}

extension SessionMonitorWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        result.rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn,
              let columnIndex = tableView.tableColumns.firstIndex(of: column),
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
