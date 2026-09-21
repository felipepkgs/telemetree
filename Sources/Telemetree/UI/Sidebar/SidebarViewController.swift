import AppKit
import Combine

private struct MoveTarget {
    let documentID: UUID
    let folderID: UUID?
}

private struct SnippetMoveTarget {
    let snippetID: UUID
    let folderID: UUID?
}

private enum LabelTarget {
    case queryDocument(UUID)
    case queryFolder(UUID)
    case snippet(UUID)
    case snippetFolder(UUID)
}

private struct LabelAssignment {
    let target: LabelTarget
    let color: LabelColor?
}

@MainActor
final class SidebarViewController: NSViewController {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var newConnectionController: NewConnectionWindowController?
    private var snippetEditorControllers: [UUID: SnippetEditorWindowController] = [:]

    private let connectionsHeader = SidebarNode(kind: .sectionHeader("Connections"))
    private let queriesHeader = SidebarNode(kind: .sectionHeader("Queries"))
    private let snippetsHeader = SidebarNode(kind: .sectionHeader("Snippets"))
    private lazy var rootNodes: [SidebarNode] = [connectionsHeader, queriesHeader, snippetsHeader]

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let contextMenu = NSMenu()
    private let footer = NSView()
    private let searchField = NSSearchField()
    private var trashActions: [NSButton: () -> Void] = [:]

    private var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            rebuildQueriesTree()
            rebuildSnippetsTree()
            if !searchText.isEmpty {
                outlineView.expandItem(queriesHeader)
                outlineView.expandItem(snippetsHeader)
            }
        }
    }

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
        rebuildSnippetsTree()
        outlineView.expandItem(connectionsHeader)
        outlineView.expandItem(queriesHeader)
        applyTheme(appState.themeStore.current)
    }

    private func applyTheme(_ theme: Theme) {
        footer.layer?.backgroundColor = theme.barFillPaint.cgColor
        footer.layer?.borderColor = theme.barBorder.cgColor
        footer.layer?.borderWidth = 1
        outlineView.reloadData()
    }

    private func setupOutlineView() {
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false
        outlineView.target = self
        outlineView.doubleAction = #selector(outlineViewDoubleClicked)

        contextMenu.delegate = self
        outlineView.menu = contextMenu

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main"))
        column.title = "Sidebar"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        searchField.placeholderString = "Search queries & snippets"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

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

        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true
        footer.addSubview(addButton)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(divider)

        view.addSubview(searchField)
        view.addSubview(scrollView)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
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

        appState.snippetStore.$snippets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildSnippetsTree() }
            .store(in: &cancellables)

        appState.snippetStore.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildSnippetsTree() }
            .store(in: &cancellables)

        appState.$activeDocumentID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.outlineView.reloadData() }
            .store(in: &cancellables)

        appState.themeStore.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in self?.applyTheme(theme) }
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

        if !searchText.isEmpty {
            let matches = appState.queryStore.documents
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name < $1.name }
            queriesHeader.children = matches.map { document -> SidebarNode in
                let node = existing["doc:\(document.id)"] ?? SidebarNode(kind: .queryDocument(document))
                node.kind = .queryDocument(document)
                return node
            }
        } else {
            queriesHeader.children = buildQueryNodes(parentFolderID: nil, existingByKey: existing)
        }
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
            let node = existingByKey["qfolder:\(folder.id)"] ?? SidebarNode(kind: .queryFolder(folder))
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

    private func rebuildSnippetsTree() {
        let existing = flattenExistingNodes(snippetsHeader.children)

        if !searchText.isEmpty {
            let matches = appState.snippetStore.snippets
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name < $1.name }
            snippetsHeader.children = matches.map { snippet -> SidebarNode in
                let node = existing["snippet:\(snippet.id)"] ?? SidebarNode(kind: .snippet(snippet))
                node.kind = .snippet(snippet)
                return node
            }
        } else {
            snippetsHeader.children = buildSnippetNodes(parentFolderID: nil, existingByKey: existing)
        }
        outlineView.reloadItem(snippetsHeader, reloadChildren: true)
    }

    private func buildSnippetNodes(parentFolderID: UUID?, existingByKey: [String: SidebarNode]) -> [SidebarNode] {
        let folders = appState.snippetStore.folders
            .filter { $0.parentID == parentFolderID }
            .sorted { $0.sortOrder < $1.sortOrder }
        let snippets = appState.snippetStore.snippets
            .filter { $0.folderID == parentFolderID }
            .sorted { $0.sortOrder < $1.sortOrder }

        let folderNodes = folders.map { folder -> SidebarNode in
            let node = existingByKey["sfolder:\(folder.id)"] ?? SidebarNode(kind: .snippetFolder(folder))
            node.kind = .snippetFolder(folder)
            node.children = buildSnippetNodes(parentFolderID: folder.id, existingByKey: existingByKey)
            return node
        }
        let snippetNodes = snippets.map { snippet -> SidebarNode in
            let node = existingByKey["snippet:\(snippet.id)"] ?? SidebarNode(kind: .snippet(snippet))
            node.kind = .snippet(snippet)
            return node
        }
        return folderNodes + snippetNodes
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
        case .sectionHeader, .queryFolder, .snippetFolder, .table, .queryDocument, .snippet, .placeholder:
            break
        }
    }

    // MARK: - Add menu

    @objc private func addButtonClicked(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(menuItem("New Connection…", action: #selector(addConnection)))
        menu.addItem(.separator())
        menu.addItem(menuItem("New Query", action: #selector(addQuery)))
        menu.addItem(menuItem("New Query Folder", action: #selector(addQueryFolder)))
        menu.addItem(.separator())
        menu.addItem(menuItem("New Snippet", action: #selector(addSnippet)))
        menu.addItem(menuItem("New Snippet Folder", action: #selector(addSnippetFolder)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func addConnection() {
        let controller = NewConnectionWindowController(appState: appState)
        newConnectionController = controller
        controller.showSheet(over: view.window)
    }

    @objc private func addQuery() {
        createAndEditNewQuery(folderID: nil)
    }

    @objc private func addQueryFolder() {
        createAndEditNewQueryFolder(parentID: nil)
    }

    @objc private func addSnippet() {
        createAndEditNewSnippet(folderID: nil)
    }

    @objc private func addSnippetFolder() {
        createAndEditNewSnippetFolder(parentID: nil)
    }

    private func createAndEditNewQuery(folderID: UUID?) {
        let document = appState.queryStore.createDocument(folderID: folderID)
        rebuildQueriesTree()
        outlineView.expandItem(queriesHeader)
        if let folderID { expandQueryFolder(folderID) }
        appState.openDocument(document.id)
        startRenaming { if case .queryDocument(let d) = $0.kind { return d.id == document.id }; return false }
    }

    private func createAndEditNewQueryFolder(parentID: UUID?) {
        let folder = appState.queryStore.createFolder(parentID: parentID)
        rebuildQueriesTree()
        outlineView.expandItem(queriesHeader)
        if let parentID { expandQueryFolder(parentID) }
        startRenaming { if case .queryFolder(let f) = $0.kind { return f.id == folder.id }; return false }
    }

    private func createAndEditNewSnippet(folderID: UUID?) {
        let snippet = appState.snippetStore.createSnippet(folderID: folderID)
        rebuildSnippetsTree()
        outlineView.expandItem(snippetsHeader)
        if let folderID { expandSnippetFolder(folderID) }
        startRenaming { if case .snippet(let s) = $0.kind { return s.id == snippet.id }; return false }
    }

    private func createAndEditNewSnippetFolder(parentID: UUID?) {
        let folder = appState.snippetStore.createFolder(parentID: parentID)
        rebuildSnippetsTree()
        outlineView.expandItem(snippetsHeader)
        if let parentID { expandSnippetFolder(parentID) }
        startRenaming { if case .snippetFolder(let f) = $0.kind { return f.id == folder.id }; return false }
    }

    private func expandQueryFolder(_ folderID: UUID) {
        if let node = findNode(in: queriesHeader.children ?? [], matching: {
            if case .queryFolder(let folder) = $0.kind { return folder.id == folderID }
            return false
        }) {
            outlineView.expandItem(node)
        }
    }

    private func expandSnippetFolder(_ folderID: UUID) {
        if let node = findNode(in: snippetsHeader.children ?? [], matching: {
            if case .snippetFolder(let folder) = $0.kind { return folder.id == folderID }
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

    // MARK: - Context menu actions (queries)

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

    @objc private func newQuerySubfolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? QueryFolder else { return }
        createAndEditNewQueryFolder(parentID: folder.id)
    }

    @objc private func deleteQueryFolder(_ sender: NSMenuItem) {
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

    // MARK: - Context menu actions (snippets)

    @objc private func insertSnippet(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet else { return }
        appState.insertSnippetIntoActiveEditor(snippet.sql)
    }

    @objc private func editSnippet(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet else { return }
        openSnippetEditor(snippet.id)
    }

    @objc private func outlineViewDoubleClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return }
        if case .snippet(let snippet) = node.kind {
            openSnippetEditor(snippet.id)
        }
    }

    private func openSnippetEditor(_ snippetID: UUID) {
        if let existing = snippetEditorControllers[snippetID] {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SnippetEditorWindowController(appState: appState, snippetID: snippetID)
        snippetEditorControllers[snippetID] = controller
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.snippetEditorControllers[snippetID] = nil
            }
        }

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func duplicateSnippet(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet,
              appState.snippetStore.duplicate(snippet.id) != nil else { return }
        rebuildSnippetsTree()
    }

    @objc private func deleteSnippet(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet else { return }
        appState.snippetStore.delete(snippet.id)
        rebuildSnippetsTree()
    }

    @objc private func newSnippetInFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? SnippetFolder else { return }
        createAndEditNewSnippet(folderID: folder.id)
    }

    @objc private func newSnippetSubfolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? SnippetFolder else { return }
        createAndEditNewSnippetFolder(parentID: folder.id)
    }

    @objc private func deleteSnippetFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? SnippetFolder else { return }
        appState.snippetStore.deleteFolder(folder.id)
        rebuildSnippetsTree()
    }

    @objc private func moveSnippetToFolder(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SnippetMoveTarget else { return }
        appState.snippetStore.move(target.snippetID, toFolder: target.folderID)
        rebuildSnippetsTree()
    }

    private func buildLabelMenu(for target: LabelTarget) -> NSMenu {
        let submenu = NSMenu()
        submenu.addItem(menuItem("None", action: #selector(setLabelColor(_:)), representedObject: LabelAssignment(target: target, color: nil)))
        submenu.addItem(.separator())
        for color in LabelColor.allCases {
            let item = menuItem(color.name, action: #selector(setLabelColor(_:)), representedObject: LabelAssignment(target: target, color: color))
            item.image = color.swatchImage()
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func setLabelColor(_ sender: NSMenuItem) {
        guard let assignment = sender.representedObject as? LabelAssignment else { return }
        switch assignment.target {
        case .queryDocument(let id):
            appState.queryStore.setLabelColor(id, color: assignment.color)
        case .queryFolder(let id):
            appState.queryStore.setFolderLabelColor(id, color: assignment.color)
        case .snippet(let id):
            appState.snippetStore.setLabelColor(id, color: assignment.color)
        case .snippetFolder(let id):
            appState.snippetStore.setFolderLabelColor(id, color: assignment.color)
        }
        outlineView.reloadData()
    }

    private func buildMoveToFolderMenu(for snippet: Snippet) -> NSMenu {
        let submenu = NSMenu()
        submenu.addItem(menuItem("Root", action: #selector(moveSnippetToFolder(_:)), representedObject: SnippetMoveTarget(snippetID: snippet.id, folderID: nil)))
        for folder in appState.snippetStore.folders.sorted(by: { $0.name < $1.name }) {
            submenu.addItem(menuItem(folder.name, action: #selector(moveSnippetToFolder(_:)), representedObject: SnippetMoveTarget(snippetID: snippet.id, folderID: folder.id)))
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
            let labelItem = NSMenuItem(title: "Label", action: nil, keyEquivalent: "")
            labelItem.submenu = buildLabelMenu(for: .queryDocument(document.id))
            menu.addItem(labelItem)
            menu.addItem(.separator())
            menu.addItem(menuItem("Delete", action: #selector(deleteDocument(_:)), representedObject: document))
        case .queryFolder(let folder):
            menu.addItem(menuItem("New Query", action: #selector(newQueryInFolder(_:)), representedObject: folder))
            menu.addItem(menuItem("New Subfolder", action: #selector(newQuerySubfolder(_:)), representedObject: folder))
            menu.addItem(.separator())
            menu.addItem(menuItem("Rename", action: #selector(renameNode(_:)), representedObject: node))
            let labelItem = NSMenuItem(title: "Label", action: nil, keyEquivalent: "")
            labelItem.submenu = buildLabelMenu(for: .queryFolder(folder.id))
            menu.addItem(labelItem)
            menu.addItem(menuItem("Delete Folder", action: #selector(deleteQueryFolder(_:)), representedObject: folder))
        case .snippet(let snippet):
            menu.addItem(menuItem("Edit…", action: #selector(editSnippet(_:)), representedObject: snippet))
            menu.addItem(menuItem("Insert into Editor", action: #selector(insertSnippet(_:)), representedObject: snippet))
            menu.addItem(.separator())
            menu.addItem(menuItem("Rename", action: #selector(renameNode(_:)), representedObject: node))
            menu.addItem(menuItem("Duplicate", action: #selector(duplicateSnippet(_:)), representedObject: snippet))
            menu.addItem(.separator())
            let moveItem = NSMenuItem(title: "Move to Folder", action: nil, keyEquivalent: "")
            moveItem.submenu = buildMoveToFolderMenu(for: snippet)
            menu.addItem(moveItem)
            let labelItem = NSMenuItem(title: "Label", action: nil, keyEquivalent: "")
            labelItem.submenu = buildLabelMenu(for: .snippet(snippet.id))
            menu.addItem(labelItem)
            menu.addItem(.separator())
            menu.addItem(menuItem("Delete", action: #selector(deleteSnippet(_:)), representedObject: snippet))
        case .snippetFolder(let folder):
            menu.addItem(menuItem("New Snippet", action: #selector(newSnippetInFolder(_:)), representedObject: folder))
            menu.addItem(menuItem("New Subfolder", action: #selector(newSnippetSubfolder(_:)), representedObject: folder))
            menu.addItem(.separator())
            menu.addItem(menuItem("Rename", action: #selector(renameNode(_:)), representedObject: node))
            let labelItem = NSMenuItem(title: "Label", action: nil, keyEquivalent: "")
            labelItem.submenu = buildLabelMenu(for: .snippetFolder(folder.id))
            menu.addItem(labelItem)
            menu.addItem(menuItem("Delete Folder", action: #selector(deleteSnippetFolder(_:)), representedObject: folder))
        case .sectionHeader, .database, .table, .placeholder:
            break
        }
    }
}

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
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
        case .snippet(let snippet):
            appState.insertSnippetIntoActiveEditor(snippet.sql)
        case .sectionHeader, .database, .queryFolder, .snippetFolder, .placeholder:
            break
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === searchField else { return }
        searchText = field.stringValue
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
        case .snippet(let snippet):
            if newName.isEmpty || newName == snippet.name {
                textField.stringValue = node.title
            } else {
                appState.snippetStore.rename(snippet.id, to: newName)
            }
        case .snippetFolder(let folder):
            if newName.isEmpty || newName == folder.name {
                textField.stringValue = node.title
            } else {
                appState.snippetStore.renameFolder(folder.id, to: newName)
            }
        default:
            textField.stringValue = node.title
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")

        let cell: HoverTrackingCellView
        let textField: NSTextField
        let imageView: NSImageView
        let dotView: StatusDotView
        let labelDotView: NSView
        let trashButton: NSButton
        let dotIdentifier = NSUserInterfaceItemIdentifier("StatusDot")
        let labelDotIdentifier = NSUserInterfaceItemIdentifier("LabelDot")
        let trashIdentifier = NSUserInterfaceItemIdentifier("TrashButton")

        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? HoverTrackingCellView,
           let reusedText = reused.textField, let reusedImage = reused.imageView,
           let reusedDot = reused.subviews.first(where: { $0.identifier == dotIdentifier }) as? StatusDotView,
           let reusedLabelDot = reused.subviews.first(where: { $0.identifier == labelDotIdentifier }),
           let reusedTrash = reused.subviews.first(where: { $0.identifier == trashIdentifier }) as? NSButton {
            cell = reused
            textField = reusedText
            imageView = reusedImage
            dotView = reusedDot
            labelDotView = reusedLabelDot
            trashButton = reusedTrash
        } else {
            cell = HoverTrackingCellView()
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

            dotView = StatusDotView(theme: appState.themeStore.current)
            dotView.identifier = dotIdentifier
            dotView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(dotView)

            labelDotView = NSView()
            labelDotView.identifier = labelDotIdentifier
            labelDotView.wantsLayer = true
            labelDotView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(labelDotView)

            trashButton = NSButton(image: AppIcon.trash.image, target: nil, action: nil)
            trashButton.identifier = trashIdentifier
            trashButton.isBordered = false
            trashButton.bezelStyle = .inline
            trashButton.contentTintColor = .systemRed
            trashButton.isHidden = true
            trashButton.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(trashButton)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -18),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

                dotView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                dotView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                dotView.widthAnchor.constraint(equalToConstant: 8),
                dotView.heightAnchor.constraint(equalToConstant: 8),

                labelDotView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                labelDotView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                labelDotView.widthAnchor.constraint(equalToConstant: 8),
                labelDotView.heightAnchor.constraint(equalToConstant: 8),

                trashButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                trashButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                trashButton.widthAnchor.constraint(equalToConstant: 14),
                trashButton.heightAnchor.constraint(equalToConstant: 14)
            ])
        }

        labelDotView.layer?.cornerRadius = 4

        textField.stringValue = node.title
        textField.textColor = .labelColor
        textField.isEditable = false
        imageView.isHidden = false
        dotView.isHidden = true
        labelDotView.isHidden = true
        trashButton.isHidden = true
        trashButton.target = nil
        trashButton.action = nil
        cell.onHoverChange = nil

        if let color = labelColorValue(for: node.kind) {
            labelDotView.isHidden = false
            labelDotView.layer?.backgroundColor = color.color.cgColor
        }

        if let deleteAction = deleteAction(for: node) {
            cell.onHoverChange = { [weak trashButton, weak labelDotView] hovering in
                trashButton?.isHidden = !hovering
                if hovering { labelDotView?.isHidden = true }
            }
            trashButton.target = self
            trashButton.action = #selector(self.trashButtonTapped(_:))
            trashButton.identifier = trashIdentifier
            trashActions[trashButton] = deleteAction
        }

        switch node.kind {
        case .sectionHeader:
            textField.font = FontLibrary.sans(11, weight: .semibold)
            imageView.isHidden = true
        case .connection(let profile):
            textField.font = FontLibrary.sans(12, weight: .bold)
            let connected = appState.connectionManager.connectedIDs.contains(profile.id)
            imageView.image = AppIcon.connection.image
            imageView.contentTintColor = nil
            dotView.isHidden = false
            dotView.theme = appState.themeStore.current
            dotView.isActive = connected
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
        case .snippetFolder:
            textField.font = FontLibrary.sans(12)
            textField.isEditable = true
            imageView.image = AppIcon.folder.image
            imageView.contentTintColor = nil
        case .snippet:
            textField.font = FontLibrary.sans(12)
            textField.isEditable = true
            imageView.image = AppIcon.snippet.image
            imageView.contentTintColor = nil
        case .placeholder:
            textField.font = FontLibrary.sans(11)
            textField.textColor = .secondaryLabelColor
            imageView.image = AppIcon.warning.image
            imageView.contentTintColor = nil
        }

        return cell
    }

    private func labelColorValue(for kind: SidebarNode.Kind) -> LabelColor? {
        switch kind {
        case .queryDocument(let document): return document.labelColor
        case .queryFolder(let folder): return folder.labelColor
        case .snippet(let snippet): return snippet.labelColor
        case .snippetFolder(let folder): return folder.labelColor
        default: return nil
        }
    }

    private func deleteAction(for node: SidebarNode) -> (() -> Void)? {
        switch node.kind {
        case .queryDocument(let document):
            return { [weak self] in self?.confirmDelete(title: document.name) {
                self?.appState.closeDocument(document.id)
                self?.appState.queryStore.delete(document.id)
                self?.rebuildQueriesTree()
            } }
        case .queryFolder(let folder):
            return { [weak self] in self?.confirmDelete(title: folder.name, isFolder: true) {
                self?.appState.queryStore.deleteFolder(folder.id)
                self?.rebuildQueriesTree()
            } }
        case .snippet(let snippet):
            return { [weak self] in self?.confirmDelete(title: snippet.name) {
                self?.appState.snippetStore.delete(snippet.id)
                self?.rebuildSnippetsTree()
            } }
        case .snippetFolder(let folder):
            return { [weak self] in self?.confirmDelete(title: folder.name, isFolder: true) {
                self?.appState.snippetStore.deleteFolder(folder.id)
                self?.rebuildSnippetsTree()
            } }
        default:
            return nil
        }
    }

    private func confirmDelete(title: String, isFolder: Bool = false, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(title)”?"
        alert.informativeText = isFolder
            ? "Its contents will be moved to the root. This cannot be undone."
            : "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard let window = view.window else {
            action()
            return
        }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                action()
            }
        }
    }

    @objc private func trashButtonTapped(_ sender: NSButton) {
        trashActions[sender]?()
    }
}
