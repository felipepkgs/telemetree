import AppKit

private struct TableStructureRow {
    let column: DatabaseColumn
    let key: String
}

/// A focused, read-only schema view. It uses the driver's structured
/// metadata methods rather than attempting to infer columns from the text of
/// a CREATE TABLE statement, which varies considerably between engines.
@MainActor
final class TableStructureWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let appState: AppState
    private let profile: ConnectionProfile
    private let database: String
    private let table: String
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "Loading structure…")
    private let indexesLabel = NSTextField(wrappingLabelWithString: "")
    private let definitionView = NSTextView()
    private var rows: [TableStructureRow] = []

    init(appState: AppState, profile: ConnectionProfile, database: String, table: String) {
        self.appState = appState
        self.profile = profile
        self.database = database
        self.table = table
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Structure · \(table)"
        window.minSize = NSSize(width: 560, height: 380)
        super.init(window: window)
        buildUI()
        loadStructure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = appState.themeStore.current.palette.window.cgColor

        let title = NSTextField(labelWithString: table)
        title.font = FontLibrary.sans(17, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let source = NSTextField(labelWithString: "\(profile.name)  ·  \(database)")
        source.font = FontLibrary.sans(11)
        source.textColor = .secondaryLabelColor
        source.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = FontLibrary.sans(11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        ["Column", "Type", "Nullable", "Default", "Key"].enumerated().forEach { index, title in
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("structure\(index)"))
            column.title = title
            column.width = [150, 170, 76, 180, 150][index]
            column.minWidth = index == 0 ? 100 : 60
            tableView.addTableColumn(column)
        }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .inset
        tableView.rowHeight = 23

        let tableScroll = NSScrollView()
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false

        let indexesTitle = NSTextField(labelWithString: "Indexes")
        indexesTitle.font = FontLibrary.sans(12, weight: .semibold)
        indexesTitle.translatesAutoresizingMaskIntoConstraints = false
        indexesLabel.font = FontLibrary.mono(11)
        indexesLabel.textColor = .secondaryLabelColor
        indexesLabel.maximumNumberOfLines = 2
        indexesLabel.lineBreakMode = .byTruncatingTail
        indexesLabel.translatesAutoresizingMaskIntoConstraints = false

        let definitionTitle = NSTextField(labelWithString: "Definition")
        definitionTitle.font = FontLibrary.sans(12, weight: .semibold)
        definitionTitle.translatesAutoresizingMaskIntoConstraints = false
        definitionView.font = FontLibrary.mono(11)
        definitionView.isEditable = false
        definitionView.drawsBackground = false
        definitionView.textColor = appState.themeStore.current.palette.secondaryText

        let definitionScroll = NSScrollView()
        definitionScroll.documentView = definitionView
        definitionScroll.hasVerticalScroller = true
        definitionScroll.borderType = .bezelBorder
        definitionScroll.translatesAutoresizingMaskIntoConstraints = false

        [title, source, statusLabel, tableScroll, indexesTitle, indexesLabel, definitionTitle, definitionScroll].forEach(content.addSubview)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            source.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),
            source.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            statusLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            tableScroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            tableScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            tableScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 165),
            indexesTitle.topAnchor.constraint(equalTo: tableScroll.bottomAnchor, constant: 12),
            indexesTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            indexesLabel.topAnchor.constraint(equalTo: indexesTitle.bottomAnchor, constant: 4),
            indexesLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            indexesLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            definitionTitle.topAnchor.constraint(equalTo: indexesLabel.bottomAnchor, constant: 12),
            definitionTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            definitionScroll.topAnchor.constraint(equalTo: definitionTitle.bottomAnchor, constant: 4),
            definitionScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            definitionScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            definitionScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            definitionScroll.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func loadStructure() {
        guard let connection = appState.connectionManager.connection(for: profile.id) else {
            statusLabel.stringValue = "Connection is no longer available."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                async let columns = connection.tableColumns(table: table, inDatabase: database)
                async let primaryKey = connection.primaryKeyColumns(table: table, inDatabase: database)
                async let foreignKeys = connection.foreignKeys(table: table, inDatabase: database)
                async let indexes = connection.indexes(table: table, inDatabase: database)
                async let definition = connection.tableDefinition(table: table, inDatabase: database)
                let (loadedColumns, loadedPK, loadedFKs, loadedIndexes, loadedDefinition) = try await (columns, primaryKey, foreignKeys, indexes, definition)
                let foreignKeysByColumn = Dictionary(uniqueKeysWithValues: loadedFKs.map { ($0.column, $0) })
                rows = loadedColumns.map { column in
                    var tags: [String] = loadedPK.contains(column.name) ? ["PK"] : []
                    if let fk = foreignKeysByColumn[column.name] { tags.append("FK → \(fk.referencedTable).\(fk.referencedColumn)") }
                    return TableStructureRow(column: column, key: tags.joined(separator: "  "))
                }
                indexesLabel.stringValue = loadedIndexes.isEmpty
                    ? "No secondary indexes"
                    : loadedIndexes.map { "\($0.isUnique ? "UNIQUE " : "")\($0.name) (\($0.columns.joined(separator: ", ")))" }.joined(separator: "   ·   ")
                definitionView.string = loadedDefinition.isEmpty ? "No definition available." : loadedDefinition
                statusLabel.stringValue = "\(loadedColumns.count) column(s)"
                tableView.reloadData()
            } catch {
                statusLabel.stringValue = "Could not load structure: \(error.localizedDescription)"
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, rows.indices.contains(row),
              let index = tableView.tableColumns.firstIndex(of: tableColumn) else { return nil }
        let identifier = tableColumn.identifier
        let label = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }()
        let item = rows[row]
        let value: String = switch index {
        case 0: item.column.name
        case 1: item.column.type
        case 2: item.column.isNullable ? "YES" : "NO"
        case 3: item.column.defaultValue ?? "—"
        default: item.key.isEmpty ? "—" : item.key
        }
        label.textField?.font = index == 0 ? FontLibrary.mono(11, weight: .medium) : FontLibrary.mono(11)
        label.textField?.stringValue = value
        label.textField?.textColor = index == 4 && !item.key.isEmpty ? appState.themeStore.current.palette.accent : appState.themeStore.current.palette.text
        return label
    }
}
