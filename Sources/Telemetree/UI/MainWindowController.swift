import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    private let appState: AppState
    private let sidebarVC: SidebarViewController
    private var queryHistoryController: QueryHistoryWindowController?
    private var commandPaletteController: CommandPaletteWindowController?

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Telemetree"
        window.minSize = NSSize(width: 900, height: 600)
        window.isRestorable = false
        window.center()

        let splitViewController = NSSplitViewController()
        let sidebarVC = SidebarViewController(appState: appState)
        self.sidebarVC = sidebarVC
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 340

        let workspaceVC = WorkspaceViewController(appState: appState)
        let workspaceItem = NSSplitViewItem(viewController: workspaceVC)

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(workspaceItem)

        super.init(window: window)
        window.contentViewController = splitViewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func newQuery(_ sender: Any?) {
        appState.newDocument()
    }

    @objc func closeActiveTab(_ sender: Any?) {
        guard let documentID = appState.activeDocumentID else { return }
        appState.closeDocument(documentID)
    }

    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let themeID = sender.representedObject as? String,
              let theme = Theme.all.first(where: { $0.id == themeID }) else { return }
        appState.themeStore.select(theme)
    }

    @objc func focusGlobalSearch(_ sender: Any?) {
        sidebarVC.focusSearch()
    }

    @objc func selectDocumentTab(_ sender: NSMenuItem) {
        let index = sender.tag - 1
        guard index >= 0, index < appState.openDocumentIDs.count else { return }
        appState.activate(appState.openDocumentIDs[index])
    }

    @objc func showQueryHistory(_ sender: Any?) {
        let controller = queryHistoryController ?? QueryHistoryWindowController(appState: appState)
        queryHistoryController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showCommandPalette(_ sender: Any?) {
        let controller = commandPaletteController ?? CommandPaletteWindowController(appState: appState) { [weak self] in
            self?.showQueryHistory(nil)
        }
        commandPaletteController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let themeID = menuItem.representedObject as? String {
            menuItem.state = (appState.themeStore.current.id == themeID) ? .on : .off
        }
        if menuItem.action == #selector(selectDocumentTab(_:)) {
            return menuItem.tag - 1 < appState.openDocumentIDs.count
        }
        return true
    }
}
