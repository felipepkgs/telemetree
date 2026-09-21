import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    private let appState: AppState

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
        super.init(window: window)

        let splitViewController = NSSplitViewController()

        let sidebarVC = SidebarViewController(appState: appState)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 340

        let workspaceVC = WorkspaceViewController(appState: appState)
        let workspaceItem = NSSplitViewItem(viewController: workspaceVC)

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(workspaceItem)

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
}
