import AppKit
import Combine

@MainActor
final class SidebarViewController: NSViewController {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var connections: [SidebarNode] = []

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()

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
        setupOutlineView()
        bind()
        rebuildConnections()
    }

    private func setupOutlineView() {
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main"))
        column.title = "Sidebar"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New Connection") ?? NSImage(),
            target: self,
            action: #selector(addConnection)
        )
        addButton.isBordered = false
        addButton.bezelStyle = .texturedRounded
        addButton.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(addButton)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(divider)

        view.addSubview(scrollView)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),

            divider.topAnchor.constraint(equalTo: footer.topAnchor),
            divider.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: footer.trailingAnchor),

            addButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 6),
            addButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
    }

    private func bind() {
        appState.connectionManager.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildConnections() }
            .store(in: &cancellables)

        appState.connectionManager.$connectedIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.outlineView.reloadData() }
            .store(in: &cancellables)
    }

    private func rebuildConnections() {
        let existingByID = Dictionary(uniqueKeysWithValues: connections.compactMap { node -> (UUID, SidebarNode)? in
            if case .connection(let profile) = node.kind { return (profile.id, node) }
            return nil
        })
        connections = appState.connectionManager.profiles.map { profile in
            existingByID[profile.id] ?? SidebarNode(kind: .connection(profile))
        }
        outlineView.reloadData()
    }

    private func loadChildrenIfNeeded(for node: SidebarNode) {
        guard !node.childrenLoaded else { return }
        node.childrenLoaded = true

        switch node.kind {
        case .connection(let profile):
            Task {
                if !appState.connectionManager.connectedIDs.contains(profile.id) {
                    await appState.connectionManager.connect(profile)
                }
                guard let connection = appState.connectionManager.connection(for: profile.id) else {
                    let message = appState.connectionManager.connectionErrors[profile.id] ?? "Failed to connect"
                    node.children = [SidebarNode(kind: .placeholder(message))]
                    outlineView.reloadItem(node, reloadChildren: true)
                    return
                }
                let systemDatabases: Set<String> = ["information_schema", "performance_schema", "mysql", "sys"]
                let databases = (try? await connection.listDatabases())?.filter { !systemDatabases.contains($0) } ?? []
                node.children = databases.map { SidebarNode(kind: .database(profile, name: $0)) }
                outlineView.reloadItem(node, reloadChildren: true)
            }
        case .database(let profile, let database):
            Task {
                guard let connection = appState.connectionManager.connection(for: profile.id) else { return }
                let tables = (try? await connection.listTables(inDatabase: database)) ?? []
                node.children = tables.map { SidebarNode(kind: .table(profile, database: database, table: $0)) }
                outlineView.reloadItem(node, reloadChildren: true)
            }
        case .table, .placeholder:
            break
        }
    }

    @objc private func addConnection() {
        let controller = NewConnectionWindowController(appState: appState)
        controller.showSheet(over: view.window)
    }
}

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        nodes(for: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        nodes(for: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.isExpandable ?? false
    }

    private func nodes(for item: Any?) -> [SidebarNode] {
        guard let node = item as? SidebarNode else { return connections }
        return node.children ?? []
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? SidebarNode else { return }
        loadChildrenIfNeeded(for: node)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return }
        switch node.kind {
        case .connection(let profile):
            appState.selectedProfileID = profile.id
        case .table(let profile, let database, let table):
            appState.selectedProfileID = profile.id
            appState.runQuery("SELECT * FROM `\(database)`.`\(table.name)` LIMIT 100;")
        case .database, .placeholder:
            break
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")

        let cell: NSTableCellView
        let textField: NSTextField
        let imageView: NSImageView

        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
           let reusedText = reused.textField, let reusedImage = reused.imageView {
            cell = reused
            textField = reusedText
            imageView = reusedImage
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView

            textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        textField.stringValue = node.title
        textField.textColor = .labelColor

        switch node.kind {
        case .connection(let profile):
            textField.font = .boldSystemFont(ofSize: 12)
            let connected = appState.connectionManager.connectedIDs.contains(profile.id)
            imageView.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)
            imageView.contentTintColor = connected ? .systemGreen : .secondaryLabelColor
        case .database:
            textField.font = .systemFont(ofSize: 12)
            imageView.image = NSImage(systemSymbolName: "cylinder", accessibilityDescription: nil)
            imageView.contentTintColor = .secondaryLabelColor
        case .table:
            textField.font = .systemFont(ofSize: 12)
            imageView.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
            imageView.contentTintColor = .secondaryLabelColor
        case .placeholder:
            textField.font = .systemFont(ofSize: 11)
            textField.textColor = .secondaryLabelColor
            imageView.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            imageView.contentTintColor = .secondaryLabelColor
        }

        return cell
    }
}
