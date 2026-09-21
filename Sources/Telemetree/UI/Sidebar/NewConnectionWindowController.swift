import AppKit

@MainActor
final class NewConnectionWindowController: NSWindowController {
    private let appState: AppState

    private let nameField = NSTextField(string: "")
    private let hostField = NSTextField(string: "127.0.0.1")
    private let portField = NSTextField(string: "3306")
    private let usernameField = NSTextField(string: "root")
    private let passwordField = NSSecureTextField()
    private let databaseField = NSTextField(string: "")
    private let sslCheckbox = NSButton(checkboxWithTitle: "Use SSL", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "New Connection"
        window.isRestorable = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSheet(over parentWindow: NSWindow?) {
        guard let parentWindow, let sheetWindow = window else { return }
        parentWindow.beginSheet(sheetWindow)
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        passwordField.placeholderString = "Password"

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = FontLibrary.sans(11)

        let grid = NSGridView(views: [
            [label("Name"), nameField],
            [label("Host"), hostField],
            [label("Port"), portField],
            [label("Username"), usernameField],
            [label("Password"), passwordField],
            [label("Database"), databaseField],
            [NSGridCell.emptyContentView, sslCheckbox]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 200
        grid.translatesAutoresizingMaskIntoConstraints = false

        let testButton = NSButton(title: "Test Connection", target: self, action: #selector(testConnection))
        let testRow = NSStackView(views: [testButton, progressIndicator, statusLabel])
        testRow.orientation = .horizontal
        testRow.spacing = 8
        testRow.alignment = .centerY

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let mainStack = NSStackView(views: [grid, testRow, buttonRow])
        mainStack.orientation = .vertical
        mainStack.spacing = 16
        mainStack.alignment = .trailing
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // The window was given a fixed, arbitrary content size at creation
        // (380x320) with the grid stretched to fill it — the grid's own
        // labels+fields never actually needed that much width, so the
        // extra space sat as a dead gap on the right, only the button row
        // pulling all the way over via mainStack's trailing alignment
        // (felipepkgs/telemetree#3, "decentered"). Sizing the window to
        // the stack's own natural fitting size removes that gap outright
        // instead of fighting NSGridView's column-stretch behavior.
        window?.setContentSize(mainStack.fittingSize)
    }

    private func makeProfile() -> ConnectionProfile {
        ConnectionProfile(
            name: nameField.stringValue,
            host: hostField.stringValue,
            port: Int(portField.stringValue) ?? 3306,
            username: usernameField.stringValue,
            database: databaseField.stringValue,
            useSSL: sslCheckbox.state == .on
        )
    }

    @objc private func testConnection() {
        statusLabel.stringValue = ""
        progressIndicator.startAnimation(nil)
        let profile = makeProfile()
        let password = passwordField.stringValue
        Task {
            let result = await appState.connectionManager.testConnection(profile, password: password)
            progressIndicator.stopAnimation(nil)
            switch result {
            case .success:
                statusLabel.stringValue = "Success"
                statusLabel.textColor = .systemGreen
            case .failure(let error):
                statusLabel.stringValue = "Failed: \(error.localizedDescription)"
                statusLabel.textColor = .systemRed
            }
        }
    }

    @objc private func save() {
        guard !nameField.stringValue.isEmpty, !hostField.stringValue.isEmpty else { return }
        appState.connectionManager.addProfile(makeProfile(), password: passwordField.stringValue)
        dismissSheet()
    }

    @objc private func cancel() {
        dismissSheet()
    }

    private func dismissSheet() {
        if let sheetWindow = window, let parent = sheetWindow.sheetParent {
            parent.endSheet(sheetWindow)
        }
    }
}
