import AppKit
import Combine

@MainActor
final class MainWindowController: NSWindowController {
    private let appState: AppState
    private let sidebarVC: SidebarViewController
    private let workspaceVC: NSSplitViewController
    private var chooserVC: ConnectionChooserViewController?
    private var switchChooserWindowController: NSWindowController?
    private var queryHistoryController: QueryHistoryWindowController?
    private var commandPaletteController: CommandPaletteWindowController?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Telemetree"
        window.backgroundColor = appState.themeStore.current.palette.window
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
        self.workspaceVC = splitViewController

        super.init(window: window)
        appState.themeStore.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak window] theme in window?.backgroundColor = theme.palette.window }
            .store(in: &cancellables)
        showConnectionChooser(nil)
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

    @objc func focusGlobalSearch(_ sender: Any?) {
        if window?.contentViewController === workspaceVC { sidebarVC.focusSearch() }
        else { showConnectionChooser(nil) }
    }

    @objc func showConnectionChooser(_ sender: Any?) {
        if window?.contentViewController === workspaceVC {
            presentSwitchChooser()
            return
        }
        let chooser = ConnectionChooserViewController(appState: appState) { [weak self] in
            guard let self else { return }
            self.window?.contentViewController = self.workspaceVC
            self.chooserVC = nil
        }
        chooserVC = chooser
        window?.contentViewController = chooser
    }

    private func presentSwitchChooser() {
        guard let window, switchChooserWindowController == nil else { return }
        let chooser = ConnectionChooserViewController(
            appState: appState,
            showsCancelButton: true,
            onOpen: { [weak self] in self?.dismissSwitchChooser() },
            onCancel: { [weak self] in self?.dismissSwitchChooser() }
        )
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Switch Connection or Database"
        sheet.contentViewController = chooser
        switchChooserWindowController = NSWindowController(window: sheet)
        window.beginSheet(sheet)
    }

    private func dismissSwitchChooser() {
        guard let sheet = switchChooserWindowController?.window else { return }
        sheet.sheetParent?.endSheet(sheet)
        switchChooserWindowController = nil
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
        if menuItem.action == #selector(selectDocumentTab(_:)) {
            return menuItem.tag - 1 < appState.openDocumentIDs.count
        }
        return true
    }
}
