import AppKit
import Combine

@MainActor
final class WorkspaceStatusBarView: NSView {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var documentCancellables = Set<AnyCancellable>()
    private let connectionLabel = NSTextField(labelWithString: "No connection")
    private let executionLabel = NSTextField(labelWithString: "No query run")
    private let statusBar = NSView()

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)
        setupUI()
        bind()
        bindActiveDocument()
        updateConnection()
        updateExecution()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        statusBar.wantsLayer = true
        statusBar.layer?.cornerRadius = 5
        connectionLabel.font = FontLibrary.sans(11, weight: .medium)
        executionLabel.font = FontLibrary.mono(11)
        connectionLabel.lineBreakMode = .byTruncatingMiddle
        connectionLabel.setAccessibilityLabel("Current connection and database")
        executionLabel.setAccessibilityLabel("Current query execution time")
        connectionLabel.translatesAutoresizingMaskIntoConstraints = false
        executionLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusBar)
        statusBar.addSubview(connectionLabel)
        statusBar.addSubview(executionLabel)
        NSLayoutConstraint.activate([
            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            statusBar.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            connectionLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 9),
            connectionLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            connectionLabel.trailingAnchor.constraint(lessThanOrEqualTo: executionLabel.leadingAnchor, constant: -12),
            executionLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -9),
            executionLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
    }

    private func bind() {
        appState.connectionManager.$profiles.sink { [weak self] _ in self?.updateConnection() }.store(in: &cancellables)
        appState.connectionManager.$connectedIDs.sink { [weak self] _ in self?.updateConnection() }.store(in: &cancellables)
        appState.connectionManager.$currentDatabases.sink { [weak self] _ in self?.updateConnection() }.store(in: &cancellables)
        appState.$pendingDatabases.sink { [weak self] _ in self?.updateConnection() }.store(in: &cancellables)
        appState.$databaseSwitchErrors.sink { [weak self] _ in self?.updateConnection() }.store(in: &cancellables)
        appState.$activeDocumentID.sink { [weak self] _ in self?.bindActiveDocument() }.store(in: &cancellables)
        appState.themeStore.$current.sink { [weak self] theme in self?.applyTheme(theme) }.store(in: &cancellables)
    }

    private func bindActiveDocument() {
        documentCancellables.removeAll()
        guard let state = appState.activeState else {
            updateConnection()
            updateExecution()
            return
        }
        state.$connectionProfileID.sink { [weak self] _ in self?.updateConnection() }.store(in: &documentCancellables)
        state.$tableBrowseContext.sink { [weak self] _ in self?.updateConnection() }.store(in: &documentCancellables)
        state.$isExecuting.sink { [weak self] _ in self?.updateExecution() }.store(in: &documentCancellables)
        state.$executionDuration.sink { [weak self] _ in self?.updateExecution() }.store(in: &documentCancellables)
        state.$errorMessage.sink { [weak self] _ in self?.updateExecution() }.store(in: &documentCancellables)
        updateConnection()
        updateExecution()
    }

    private func updateConnection() {
        guard let profile = appState.selectedProfile else {
            connectionLabel.stringValue = "No connection selected"
            connectionLabel.textColor = .secondaryLabelColor
            connectionLabel.toolTip = nil
            return
        }
        let browseDatabase = appState.activeState?.tableBrowseContext.flatMap { $0.profileID == profile.id ? $0.database : nil }
        let database = browseDatabase ?? appState.connectionManager.currentDatabases[profile.id] ?? profile.database
        let databaseName = profile.engine.connectsToFile
            ? URL(fileURLWithPath: profile.filePath).lastPathComponent
            : (database.isEmpty ? "No database" : database)
        let state = appState.connectionManager.connectedIDs.contains(profile.id) ? "Connected" : "Disconnected"
        if let pending = appState.pendingDatabases[profile.id] {
            connectionLabel.stringValue = "\(profile.name)  ·  Switching to \(pending)…"
            connectionLabel.textColor = .controlAccentColor
        } else if let error = appState.databaseSwitchErrors[profile.id] {
            connectionLabel.stringValue = "\(profile.name)  ·  \(databaseName)  ·  Switch failed"
            connectionLabel.textColor = .systemRed
            connectionLabel.toolTip = error
        } else {
            let tableView = browseDatabase == nil ? "" : "Table view  ·  "
            connectionLabel.stringValue = "\(profile.name)  ·  \(databaseName)  ·  \(tableView)\(state)"
            connectionLabel.textColor = .secondaryLabelColor
            connectionLabel.toolTip = nil
        }
    }

    private func updateExecution() {
        guard let state = appState.activeState else {
            executionLabel.stringValue = "No query run"
            executionLabel.textColor = .secondaryLabelColor
            return
        }
        if state.isExecuting {
            executionLabel.stringValue = "Executing…"
            executionLabel.textColor = .controlAccentColor
        } else if let duration = state.executionDuration {
            executionLabel.stringValue = state.errorMessage == nil
                ? String(format: "Last query  %.3f s", duration)
                : String(format: "Failed  ·  %.3f s", duration)
            executionLabel.textColor = state.errorMessage == nil ? .secondaryLabelColor : .systemRed
            executionLabel.toolTip = state.errorMessage
        } else {
            executionLabel.stringValue = "No query run"
            executionLabel.textColor = .secondaryLabelColor
            executionLabel.toolTip = state.errorMessage
        }
    }

    private func applyTheme(_ theme: Theme) {
        statusBar.layer?.backgroundColor = theme.barFill.cgColor
        statusBar.layer?.borderColor = theme.barBorder.cgColor
        statusBar.layer?.borderWidth = 1
    }
}
