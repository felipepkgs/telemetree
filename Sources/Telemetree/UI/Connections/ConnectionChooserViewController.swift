import AppKit
import Combine

@MainActor
final class ConnectionChooserViewController: NSViewController {
    private let appState: AppState
    private let onOpen: () -> Void
    private let onCancel: () -> Void
    private let showsCancelButton: Bool
    private var cancellables = Set<AnyCancellable>()
    private var newConnectionController: NewConnectionWindowController?
    private var knownProfileIDs: Set<UUID> = []
    private let profilePopup = NSPopUpButton()
    private let databasePopup = NSPopUpButton()
    private let statusLabel = NSTextField(wrappingLabelWithString: "Choose a connection to load its databases.")
    private let openButton = NSButton(title: "Open Workspace", target: nil, action: nil)

    init(appState: AppState, showsCancelButton: Bool = false, onOpen: @escaping () -> Void, onCancel: @escaping () -> Void = {}) {
        self.appState = appState
        self.onOpen = onOpen
        self.onCancel = onCancel
        self.showsCancelButton = showsCancelButton
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let title = NSTextField(labelWithString: "Choose your workspace")
        title.font = FontLibrary.sans(24, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Select a connection and database before opening your SQL workbench.")
        subtitle.textColor = .secondaryLabelColor
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged)
        databasePopup.target = self
        databasePopup.action = #selector(databaseChanged)
        databasePopup.isEnabled = false
        openButton.target = self
        openButton.action = #selector(openWorkspace)
        openButton.keyEquivalent = "\r"
        openButton.bezelStyle = .rounded
        openButton.isEnabled = false
        openButton.contentTintColor = .systemGreen
        let newButton = NSButton(title: "New Connection…", target: self, action: #selector(newConnection))
        var buttons: [NSView] = []
        if showsCancelButton {
            let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
            cancelButton.bezelStyle = .rounded
            cancelButton.keyEquivalent = "\u{1b}"
            buttons.append(cancelButton)
        }
        buttons += [newButton, openButton]
        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        let fields = NSGridView(views: [
            [NSTextField(labelWithString: "Connection"), profilePopup],
            [NSTextField(labelWithString: "Database"), databasePopup]
        ])
        fields.rowSpacing = 14
        fields.columnSpacing = 14
        let stack = NSStackView(views: [title, subtitle, fields, statusLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 440),
            profilePopup.widthAnchor.constraint(equalToConstant: 290),
            databasePopup.widthAnchor.constraint(equalTo: profilePopup.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        appState.connectionManager.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadProfiles() }
            .store(in: &cancellables)
    }

    private var selectedProfile: ConnectionProfile? {
        guard let id = profilePopup.selectedItem?.representedObject as? UUID else { return nil }
        return appState.connectionManager.profiles.first { $0.id == id }
    }

    private func reloadProfiles() {
        let profiles = appState.connectionManager.profiles
        let previousID = (knownProfileIDs.isEmpty ? appState.selectedProfile?.id : profiles.first(where: { !knownProfileIDs.contains($0.id) })?.id)
            ?? selectedProfile?.id ?? appState.selectedProfile?.id
        knownProfileIDs = Set(profiles.map(\.id))
        profilePopup.removeAllItems()
        for profile in profiles {
            profilePopup.addItem(withTitle: "\(profile.name)  ·  \(profile.engine.displayName)")
            profilePopup.lastItem?.representedObject = profile.id
        }
        if let previousID, let index = profilePopup.itemArray.firstIndex(where: { ($0.representedObject as? UUID) == previousID }) {
            profilePopup.selectItem(at: index)
        }
        if profiles.isEmpty {
            statusLabel.stringValue = "No connections yet. Create one to get started."
        } else {
            profileChanged()
        }
    }

    @objc private func profileChanged() {
        guard let profile = selectedProfile else { return }
        databasePopup.removeAllItems()
        databasePopup.isEnabled = false
        openButton.isEnabled = false
        statusLabel.stringValue = "Connecting to \(profile.name)…"
        statusLabel.textColor = .secondaryLabelColor
        Task {
            if appState.connectionManager.connection(for: profile.id) == nil {
                await appState.connectionManager.connect(profile)
            }
            guard selectedProfile?.id == profile.id else { return }
            guard let connection = appState.connectionManager.connection(for: profile.id) else {
                showError(appState.connectionManager.connectionErrors[profile.id] ?? "Could not connect.")
                return
            }
            do {
                let databases = profile.engine == .mysql
                    ? try await connection.listDatabases().filter { !["information_schema", "performance_schema", "mysql", "sys"].contains($0) }
                    : [profile.engine.connectsToFile ? URL(fileURLWithPath: profile.filePath).lastPathComponent : profile.database]
                guard selectedProfile?.id == profile.id else { return }
                databasePopup.addItems(withTitles: databases)
                let current = appState.connectionManager.currentDatabases[profile.id] ?? profile.database
                databasePopup.selectItem(withTitle: current)
                if databasePopup.selectedItem == nil { databasePopup.selectItem(at: 0) }
                databasePopup.isEnabled = databases.count > 1
                openButton.isEnabled = !databases.isEmpty
                statusLabel.stringValue = databases.isEmpty ? "No databases available for this connection." : "\(databases.count) database\(databases.count == 1 ? "" : "s") available"
            } catch {
                guard selectedProfile?.id == profile.id else { return }
                showError(error.localizedDescription)
            }
        }
    }

    @objc private func databaseChanged() { statusLabel.stringValue = "Ready to open \(databasePopup.titleOfSelectedItem ?? "")" }

    @objc private func cancel() { onCancel() }

    @objc private func openWorkspace() {
        guard let profile = selectedProfile, let database = databasePopup.titleOfSelectedItem else { return }
        openButton.isEnabled = false
        Task {
            let success = await appState.selectDatabase(database, profileID: profile.id)
            guard selectedProfile?.id == profile.id else { return }
            if success { onOpen() }
            else {
                showError(appState.databaseSwitchErrors[profile.id] ?? "Could not select the database.")
                openButton.isEnabled = true
            }
        }
    }

    @objc private func newConnection() {
        let controller = NewConnectionWindowController(appState: appState)
        newConnectionController = controller
        controller.showSheet(over: view.window)
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed
    }
}
