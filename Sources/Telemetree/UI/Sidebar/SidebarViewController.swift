import AppKit
import Combine

private struct MoveTarget {
    let documentID: UUID
    let folderID: UUID?
}

@MainActor
final class SidebarViewController: NSViewController {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    private let connectionsHeader = SidebarNode(kind: .sectionHeader("Connections"))
    private let queriesHeader = SidebarNode(kind: .sectionHeader("Queries"))
    private lazy var rootNodes: [SidebarNode] = [connectionsHeader, queriesHeader]

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let contextMenu = NSMenu()

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
        outlineView.reloadData()
        rebuildConnectionsTree()
        rebuildQueriesTree()
        outlineView.expandItem(connectionsHeader)
        outlineView.expandItem(queriesHeader)
    }

    private func setupOutlineView() {
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false

        contextMenu.delegate = self
        outlineView.menu = contextMenu

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main"))
        column.title = "Sidebar"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(
            image: AppIcon.add.image,
            target: self,
            action: #selector(addButtonClicked(_:))
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
            .sink { [weak self] _ in self?.rebuildConnectionsTree() }
            .store(in: &cancellables)

        appState.connectionManager.$connectedIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.outlineView.reloadData() }
            .store(in: &cancellables)

        appState.queryStore.$documents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildQueriesTree() }
            .store(in: &cancellables)

        appState.queryStore.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildQueriesTree() }
            .store(in: &cancellables)

        appState.$activeDocumentID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.outlineView.reloadData() }
            .store(in: &cancellables)
    }

    // MARK: - Tree building

    private func nodes(for item: Any?) -> [SidebarNode] {
        guard let node = item as? SidebarNode else { return rootNodes }
        return node.children ?? []
    }

    private func flattenExistingNodes(_ nodes: [SidebarNode]?) -> [String: SidebarNode] {
        var result: [String: SidebarNode] = [:]
        func visit(_ list: [SidebarNode]) {
            for node in list {
                if let key = node.identityKey { result[key] = node }
                if let children = node.children { visit(children) }
            }
        }
        visit(nodes ?? [])
        return result
    }

    private func rebuildConnectionsTree() {
        let existing = flattenExistingNodes(connectionsHeader.children)
        connectionsHeader.children = appState.connectionManager.profiles.map { profile -> SidebarNode in
            let node = existing["conn:\(profile.id)"] ?? SidebarNode(kind: .connection(profile))
            node.kind = .connection(profile)
            return node
        }
        outlineView.reloadItem(connectionsHeader, reloadChildren: true)
    }

    private func rebuildQueriesTree() {
        let existing = flattenExistingNodes(queriesHeader.children)
        queriesHeader.children = buildQueryNodes(parentFolderID: nil, existingByKey: existing)
        outlineView.reloadItem(queriesHeader, reloadChildren: true)
    }

    private func buildQueryNodes(parentFolderID: UUID?, existingByKey: [String: SidebarNode]) -> [SidebarNode] {
        let folders = appState.queryStore.folders
            .filter { $0.parentID == parentFolderID }
            .sorted { $0.sortOrder < $1.sortOrder }
        let documents = appState.queryStore.documents
            .filter { $0.folderID == parentFolderID }
            .sorted { $0.sortOrder < $1.sortOrder }

        let folderNodes = folders.map { folder -> SidebarNode in
            let node = existingByKey["folder:\(folder.id)"] ?? SidebarNode(kind: .queryFolder(folder))
            node.kind = .queryFolder(folder)
            node.children = buildQueryNodes(parentFolderID: folder.id, existingByKey: existingByKey)
            return node
        }
        let documentNodes = documents.map { document -> SidebarNode in
            let node = existingByKey["doc:\(document.id)"] ?? SidebarNode(kind: .queryDocument(document))
            node.kind = .queryDocument(document)
            return node
        }
        return folderNodes + documentNodes
    }

    private func findNode(in nodes: [SidebarNode], matching predicate: (SidebarNode) -> Bool) -> SidebarNode? {
        for node in nodes {
            if predicate(node) { return node }
            if let children = node.children, let found = findNode(in: children, matching: predicate) {
                return found
            }
        }
        return nil
    }

    // MARK: - Schema loading (connections/databases/tables)

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
        case .sectionHeader, .queryFolder, .table, .queryDocument, .placeholder:
            break
        }
    }

    // MARK: - Add menu

    @objc private func addButtonClicked(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(menuItem("New Connection…", action: #selector(addConnection)))
        menu.addItem(menuItem("New Query", action: #selector(addQuery)))
        menu.addItem(menuItem("New Folder", action: #selector(addFolder)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func addConnection() {
        let controller = NewConnectionWindowController(appState: appState)
        controller.showSheet(over: view.window)
    }

    @objc private func addQuery() {
        createAndEditNewQuery(folderID: nil)
    }

    @objc private func addFolder() {
        createAndEditNewFolder(parentID: nil)
    }

    private func createAndEditNewQuery(folderID: UUID?) {
        let document = appState.queryStore.createDocument(folderID: folderID)
        rebuildQueriesTree()
        outlineView.expandItem(queriesHeader)
        if let folderID { expandFolder(folderID) }
        appState.openDocument(document.id)
        startRenaming { if case .queryDocument(let d) = $0.kind { return d.id == document.id }; return false }
    }

    private func createAndEditNewFolder(parentID: UUID?) {
        let folder = appState.queryStore.createFolder(parentID: parentID)
        rebuildQueriesTree()
        outlineView.expandItem(queriesHeader)
        if let parentID { expandFolder(parentID) }
        startRenaming { if case .queryFolder(let f) = $0.kind { return f.id == folder.id }; return false }
    }

    private func expandFolder(_ folderID: UUID) {
        if let node = findNode(in: queriesHeader.children ?? [], matching: {
            if case .queryFolder(let folder) = $0.kind { return folder.id == folderID }
            return false
        }) {
            outlineView.expandItem(node)
        }
    }

    private func startRenaming(matching predicate: (SidebarNode) -> Bool) {
        guard let node = findNode(in: rootNodes, matching: predicate) else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.scrollRowToVisible(row)
        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    private func menuItem(_ title: String, action: Selector, representedObject: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        return item
    }

    // MARK: - Context menu actions

    @objc private func removeConnection(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? ConnectionProfile else { return }
        Task { await appState.connectionManager.disconnect(profile) }
        appState.connectionManager.deleteProfile(profile)
    }

    @objc private func renameNode(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SidebarNode else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func duplicateDocument(_ sender: NSMenuItem) {
        guard let document = sender.representedObject as? QueryDocument,
              let copy = appState.queryStore.duplicate(document.id) else { return }
        rebuildQueriesTree()
        appState.openDocument(copy.id)
    }

    @objc private func deleteDocument(_ sender: NSMenuItem) {
        guard let document = sender.representedObject as? QueryDocument else { return }
        appState.closeDocument(document.id)
        appState.queryStore.delete(document.id)
        rebuildQueriesTree()
    }

    @objc private func newQueryInFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? QueryFolder else { return }
        createAndEditNewQuery(folderID: folder.id)
    }

    @objc private func newSubfolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? QueryFolder else { return }
        createAndEditNewFolder(parentID: folder.id)
    }

    @objc private func deleteFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? QueryFolder else { return }
        appState.queryStore.deleteFolder(folder.id)
        rebuildQueriesTree()
    }

    @objc private func moveDocumentToFolder(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MoveTarget else { return }
        appState.queryStore.move(target.documentID, toFolder: target.folderID)
        rebuildQueriesTree()
    }

    private func buildMoveToFolderMenu(for document: QueryDocument) -> NSMenu {
        let submenu = NSMenu()
        submenu.addItem(menuItem("Root", action: #selector(moveDocumentToFolder(_:)), representedObject: MoveTarget(documentID: document.id, folderID: nil)))
        for folder in appState.queryStore.folders.sorted(by: { $0.name < $1.name }) {
            submenu.addItem(menuItem(folder.name, action: #selector(moveDocumentToFolder(_:)), representedObject: MoveTarget(documentID: document.id, folderID: folder.id)))
        }
        return submenu
    }
}

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return }

        switch node.kind {
        case .connection(let profile):
            menu.addItem(menuItem("Remove Connection", action: #selector(removeConnection(_:)), representedObject: profile))
        case .queryDocument(let document):
            menu.addItem(menuItem("Rename", action: #selector(renameNode(_:)), representedObject: node))
            menu.addItem(menuItem("Duplicate", action: #selector(duplicateDocument(_:)), representedObject: document))
            menu.addItem(.separator())
            let moveItem = NSMenuItem(title: "Move to Folder", action: nil, keyEquivalent: "")
            moveItem.submenu = buildMoveToFolderMenu(for: document)
            menu.addItem(moveItem)
            menu.addItem(.separator())
            menu.addItem(menuItem("Delete", action: #selector(deleteDocument(_:)), representedObject: document))
        case .queryFolder(let folder):
            menu.addItem(menuItem("New Query", action: #selector(newQueryInFolder(_:)), representedObject: folder))
            menu.addItem(menuItem("New Subfolder", action: #selector(newSubfolder(_:)), representedObject: folder))
            menu.addItem(.separator())
            menu.addItem(menuItem("Rename", action: #selector(renameNode(_:)), representedObject: node))
            menu.addItem(menuItem("Delete Folder", action: #selector(deleteFolder(_:)), representedObject: folder))
        case .sectionHeader, .database, .table, .placeholder:
            break
        }
    }
}

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        nodes(for: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        nodes(for: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.isExpandable ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.isGroupHeader ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !((item as? SidebarNode)?.isGroupHeader ?? false)
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
            appState.setActiveConnection(profile.id)
        case .table(let profile, let database, let table):
            appState.runQuery("SELECT * FROM `\(database)`.`\(table.name)` LIMIT 100;", connectionProfileID: profile.id)
        case .queryDocument(let document):
            appState.openDocument(document.id)
        case .sectionHeader, .database, .queryFolder, .placeholder:
            break
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        let row = outlineView.row(for: textField)
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return }
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch node.kind {
        case .queryDocument(let document):
            if newName.isEmpty || newName == document.name {
                textField.stringValue = node.title
            } else {
                appState.queryStore.rename(document.id, to: newName)
            }
        case .queryFolder(let folder):
            if newName.isEmpty || newName == folder.name {
                textField.stringValue = node.title
            } else {
                appState.queryStore.renameFolder(folder.id, to: newName)
            }
        default:
            textField.stringValue = node.title
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
            textField.isSelectable = true
            textField.delegate = self
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
        textField.isEditable = false
        imageView.isHidden = false

        switch node.kind {
        case .sectionHeader:
            textField.font = FontLibrary.sans(11, weight: .semibold)
            imageView.isHidden = true
        case .connection(let profile):
            textField.font = FontLibrary.sans(12, weight: .bold)
            let connected = appState.connectionManager.connectedIDs.contains(profile.id)
            imageView.image = AppIcon.connection.image
            imageView.contentTintColor = connected ? .systemGreen : nil
        case .database:
            textField.font = FontLibrary.sans(12)
            imageView.image = AppIcon.database.image
            imageView.contentTintColor = nil
        case .table:
            textField.font = FontLibrary.sans(12)
            imageView.image = AppIcon.table.image
            imageView.contentTintColor = nil
        case .queryFolder:
            textField.font = FontLibrary.sans(12)
            textField.isEditable = true
            imageView.image = AppIcon.folder.image
            imageView.contentTintColor = nil
        case .queryDocument(let document):
            let isActive = document.id == appState.activeDocumentID
            textField.font = isActive ? FontLibrary.sans(12, weight: .bold) : FontLibrary.sans(12)
            textField.isEditable = true
            imageView.image = AppIcon.document.image
            imageView.contentTintColor = isActive ? .controlAccentColor : nil
        case .placeholder:
            textField.font = FontLibrary.sans(11)
            textField.textColor = .secondaryLabelColor
            imageView.image = AppIcon.warning.image
            imageView.contentTintColor = nil
        }

        return cell
    }
}
