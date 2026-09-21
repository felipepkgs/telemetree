import AppKit

private struct PaletteItem {
    let id: String
    let title: String
    let category: String
    let action: () -> Void
}

/// ⌘⇧P — fuzzy (substring) search across query documents, snippets,
/// connections, and a handful of actions, in one place. Deliberately
/// skips live table names for now: that would need a schema-name cache
/// this app doesn't build yet (each connection's tables are only loaded
/// lazily, per database, when the sidebar asks) — a reasonable follow-up,
/// not a fit for "suggest keywords"-scoped work.
@MainActor
final class CommandPaletteWindowController: NSWindowController {
    private let appState: AppState
    private let openHistory: () -> Void

    private var allItems: [PaletteItem] = []
    private var filteredItems: [PaletteItem] = []

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    init(appState: AppState, openHistory: @escaping () -> Void) {
        self.appState = appState
        self.openHistory = openHistory
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isRestorable = false
        window.center()
        window.level = .floating
        super.init(window: window)
        buildUI()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Clear the field *before* reload()/refilter — reload() filters
        // using whatever's currently in searchField, so clearing it after
        // left the field looking empty while the row list stayed stuck on
        // the previous search's single result.
        searchField.stringValue = ""
        reload()
        window?.makeFirstResponder(searchField)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        searchField.placeholderString = "Search queries, snippets, connections, actions…"
        searchField.delegate = self
        searchField.font = FontLibrary.sans(15)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.target = self
        tableView.doubleAction = #selector(activateClickedRow)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main"))
        tableView.addTableColumn(column)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(searchField)
        contentView.addSubview(divider)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func reload() {
        var items: [PaletteItem] = []

        for document in appState.queryStore.documents.sorted(by: { $0.name < $1.name }) {
            items.append(PaletteItem(id: "query:\(document.id)", title: document.name, category: "Query") { [weak appState] in
                appState?.openDocument(document.id)
            })
        }
        for snippet in appState.snippetStore.snippets.sorted(by: { $0.name < $1.name }) {
            items.append(PaletteItem(id: "snippet:\(snippet.id)", title: snippet.name, category: "Snippet") { [weak appState] in
                appState?.insertSnippetIntoActiveEditor(snippet.sql)
            })
        }
        for profile in appState.connectionManager.profiles.sorted(by: { $0.name < $1.name }) {
            items.append(PaletteItem(id: "connection:\(profile.id)", title: profile.name, category: "Connection") { [weak appState] in
                appState?.setActiveConnection(profile.id)
            })
        }

        items.append(PaletteItem(id: "action:new-query", title: "New Query", category: "Action") { [weak appState] in
            appState?.newDocument()
        })
        items.append(PaletteItem(id: "action:new-snippet", title: "New Snippet", category: "Action") { [weak appState] in
            appState?.snippetStore.createSnippet()
        })
        items.append(PaletteItem(id: "action:run-query", title: "Run Current Query", category: "Action") { [weak appState] in
            appState?.executeCurrentSQL()
        })
        items.append(PaletteItem(id: "action:query-history", title: "Query History", category: "Action") { [weak self] in
            self?.openHistory()
        })
        for theme in Theme.all {
            items.append(PaletteItem(id: "theme:\(theme.id)", title: "Theme: \(theme.name)", category: "Action") { [weak appState] in
                appState?.themeStore.select(theme)
            })
        }

        allItems = items
        refilter(query: searchField.stringValue)
    }

    // MARK: - Usage tracking ("most used")

    private static let usageDefaultsKey = "commandPaletteUsageCounts"

    private func usageCounts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: Self.usageDefaultsKey) as? [String: Int] ?? [:]
    }

    private func recordUsage(_ id: String) {
        var counts = usageCounts()
        counts[id, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: Self.usageDefaultsKey)
    }

    private func refilter(query: String) {
        let matches = query.isEmpty ? allItems : allItems.filter { $0.title.localizedCaseInsensitiveContains(query) }
        let counts = usageCounts()
        // Most-used first (ties broken alphabetically) — applies both to
        // the empty-query default list and to search results, so a
        // frequently-used item still surfaces near the top of a broader
        // match set, not just when the palette is first opened.
        filteredItems = matches.sorted { a, b in
            let countA = counts[a.id] ?? 0
            let countB = counts[b.id] ?? 0
            if countA != countB { return countA > countB }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        tableView.reloadData()
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filteredItems.isEmpty else { return }
        let current = tableView.selectedRow
        let next = max(0, min(filteredItems.count - 1, current < 0 ? 0 : current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private func activateSelected() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard row < filteredItems.count else { return }
        let item = filteredItems[row]
        recordUsage(item.id)
        window?.close()
        item.action()
    }

    @objc private func activateClickedRow() {
        let row = tableView.clickedRow
        guard row >= 0, row < filteredItems.count else { return }
        let item = filteredItems[row]
        recordUsage(item.id)
        window?.close()
        item.action()
    }
}

extension CommandPaletteWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === searchField else { return }
        refilter(query: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            activateSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            window?.close()
            return true
        default:
            return false
        }
    }
}

extension CommandPaletteWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredItems.count else { return nil }
        let item = filteredItems[row]
        let identifier = NSUserInterfaceItemIdentifier("PaletteCell")

        let cell: NSTableCellView
        let titleField: NSTextField
        let categoryField: NSTextField

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
           let reusedTitle = reused.textField,
           let reusedCategory = reused.subviews.last as? NSTextField {
            cell = reused
            titleField = reusedTitle
            categoryField = reusedCategory
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            titleField = NSTextField(labelWithString: "")
            titleField.font = FontLibrary.sans(13)
            titleField.lineBreakMode = .byTruncatingTail
            titleField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(titleField)
            cell.textField = titleField

            categoryField = NSTextField(labelWithString: "")
            categoryField.font = FontLibrary.sans(11)
            categoryField.textColor = .secondaryLabelColor
            categoryField.alignment = .right
            categoryField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(categoryField)

            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                titleField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

                categoryField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                categoryField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                categoryField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: 8),
                categoryField.widthAnchor.constraint(equalToConstant: 70)
            ])
        }

        titleField.stringValue = item.title
        categoryField.stringValue = item.category
        return cell
    }
}
