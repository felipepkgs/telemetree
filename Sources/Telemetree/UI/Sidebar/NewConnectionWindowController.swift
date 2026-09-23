import AppKit

@MainActor
final class NewConnectionWindowController: NSWindowController {
    private let appState: AppState

    private let enginePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField(string: "")
    private let hostField = NSTextField(string: "127.0.0.1")
    private let portField = NSTextField(string: "3306")
    private let usernameField = NSTextField(string: "root")
    private let passwordField = NSSecureTextField()
    private let databaseField = NSTextField(string: "")
    private let sslCheckbox = NSButton(checkboxWithTitle: "Use SSL", target: nil, action: nil)
    private let fileField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()

    // True Optionals, not implicitly-unwrapped — both are only assigned
    // partway through buildUI(), and a real crash already happened once
    // from a call that reached updateFieldVisibility() (and so
    // resizeToFitContent()) before mainStack existed yet. IUO would
    // crash the same way if that ordering mistake is ever reintroduced;
    // a plain Optional with a guard just no-ops instead.
    private var grid: NSGridView?
    private var mainStack: NSStackView?
    private static let windowPadding: CGFloat = 20
    /// Row indices, set once the grid is built — used to toggle
    /// server-style rows (host/port/username/...) vs. the file-path row
    /// depending on the selected engine.
    private var serverRowIndices: [Int] = []
    private var fileRowIndex = 0

    private var selectedEngine: DatabaseEngine {
        DatabaseEngine.allCases[enginePopup.indexOfSelectedItem]
    }

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

        for engine in DatabaseEngine.allCases {
            enginePopup.addItem(withTitle: engine.displayName)
        }
        enginePopup.target = self
        enginePopup.action = #selector(engineChanged)

        passwordField.placeholderString = "Password"

        let chooseFileButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFile))
        let fileRow = NSStackView(views: [fileField, chooseFileButton])
        fileRow.orientation = .horizontal
        fileRow.spacing = 6
        fileField.translatesAutoresizingMaskIntoConstraints = false
        fileField.widthAnchor.constraint(equalToConstant: 155).isActive = true

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = FontLibrary.sans(11)

        let hostRow = label("Host")
        let portRow = label("Port")
        let usernameRow = label("Username")
        let passwordRow = label("Password")
        let databaseRow = label("Database")

        // Built as locals, not written into the stored properties until
        // both are fully assembled below — see the property declarations
        // for why (a real crash happened when something touched these
        // mid-construction).
        let grid = NSGridView(views: [
            [label("Engine"), enginePopup],
            [label("Name"), nameField],
            [hostRow, hostField],
            [portRow, portField],
            [usernameRow, usernameField],
            [passwordRow, passwordField],
            [databaseRow, databaseField],
            [NSGridCell.emptyContentView, sslCheckbox],
            [label("File"), fileRow]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 200
        grid.translatesAutoresizingMaskIntoConstraints = false

        // Row 0 = Engine, 1 = Name, 2-7 = server fields + SSL, 8 = File.
        serverRowIndices = Array(2...7)
        fileRowIndex = 8
        grid.row(at: fileRowIndex).isHidden = true

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
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        // Explicit constant insets on the pinning constraints, not
        // NSStackView.edgeInsets — edgeInsets read as a no-op here in
        // practice (fields sat flush against the window edges with zero
        // visible padding), so padding is applied the way that's actually
        // guaranteed to render.
        contentView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.windowPadding),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.windowPadding),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.windowPadding),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.windowPadding)
        ])

        // Only now are both fully built and safe to expose to the rest
        // of the class (engineChanged() etc., which can fire any time
        // after this).
        self.grid = grid
        self.mainStack = mainStack

        // The window was given a fixed, arbitrary content size at creation
        // (380x320) with the grid stretched to fill it — the grid's own
        // labels+fields never actually needed that much width, so the
        // extra space sat as a dead gap on the right, only the button row
        // pulling all the way over via mainStack's trailing alignment
        // (felipepkgs/telemetree#3, "decentered"). Sizing the window to
        // the stack's own natural fitting size (plus the padding above)
        // removes that gap outright instead of fighting NSGridView's
        // column-stretch behavior.
        resizeToFitContent()
    }

    /// SQLite is a single file, not a host/port/username/password server
    /// — swap which grid rows are visible instead of showing fields that
    /// don't apply and would just confuse what "Save" is about to do.
    @objc private func engineChanged() {
        updateFieldVisibility()
    }

    private func updateFieldVisibility() {
        guard let grid else { return }
        let isFile = selectedEngine.connectsToFile
        for index in serverRowIndices {
            grid.row(at: index).isHidden = isFile
        }
        grid.row(at: fileRowIndex).isHidden = !isFile
        if selectedEngine == .postgres || selectedEngine == .mysql {
            portField.stringValue = String(selectedEngine.defaultPort)
        }
        resizeToFitContent()
    }

    private func resizeToFitContent() {
        guard let mainStack else { return }
        let fitting = mainStack.fittingSize
        window?.setContentSize(NSSize(
            width: fitting.width + Self.windowPadding * 2,
            height: fitting.height + Self.windowPadding * 2
        ))
    }

    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a SQLite database file (created if it doesn't exist yet)."
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.fileField.stringValue = url.path
        }
    }

    private func makeProfile() -> ConnectionProfile {
        ConnectionProfile(
            name: nameField.stringValue,
            engine: selectedEngine,
            host: hostField.stringValue,
            port: Int(portField.stringValue) ?? selectedEngine.defaultPort,
            username: usernameField.stringValue,
            database: databaseField.stringValue,
            useSSL: sslCheckbox.state == .on,
            filePath: fileField.stringValue
        )
    }

    private var isProfileNameable: Bool {
        guard !nameField.stringValue.isEmpty else { return false }
        return selectedEngine.connectsToFile ? !fileField.stringValue.isEmpty : !hostField.stringValue.isEmpty
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
        guard isProfileNameable else { return }
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
