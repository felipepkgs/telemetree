import AppKit

@main
@MainActor
final class TelemetreeApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = TelemetreeApp()
        app.delegate = delegate
        app.mainMenu = delegate.buildMainMenu()
        app.run()
    }

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = appMenu.addItem(withTitle: "About Telemetree", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Telemetree", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Query", action: #selector(MainWindowController.newQuery(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(MainWindowController.closeActiveTab(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }

    private var windowController: MainWindowController?
    private var aboutWindowController: AboutWindowController?

    @objc private func showAbout(_ sender: Any?) {
        let controller = aboutWindowController ?? AboutWindowController()
        aboutWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let windowController = MainWindowController(appState: AppState())
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        self.windowController = windowController
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
