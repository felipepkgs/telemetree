import Foundation

/// Owns saved connection profiles and the currently-open connections.
/// Profile metadata is persisted as JSON in Application Support; passwords
/// live only in the Keychain (see KeychainManager).
@MainActor
final class ConnectionManager: ObservableObject {
    @Published private(set) var profiles: [ConnectionProfile] = []
    @Published private(set) var connectedIDs: Set<UUID> = []
    @Published var connectionErrors: [UUID: String] = [:]
    /// The database each connection is currently `USE`d against — starts
    /// at the profile's configured default on connect, updated by
    /// AppState.selectDatabase when the sidebar clicks a different one.
    /// Session state on the server, so it's per-connection, not per-tab.
    @Published private(set) var currentDatabases: [UUID: String] = [:]

    private var connections: [UUID: any DatabaseConnection] = [:]
    private let mysqlDriver: any DatabaseDriver = MySQLDriver()
    private let postgresDriver: any DatabaseDriver = PostgresDriver()
    private let sqliteDriver: any DatabaseDriver = SQLiteDriver()

    private func driver(for engine: DatabaseEngine) -> any DatabaseDriver {
        switch engine {
        case .mysql: return mysqlDriver
        case .postgres: return postgresDriver
        case .sqlite: return sqliteDriver
        }
    }
    private let storeURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Telemetree", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("connections.json")
        load()
    }

    func addProfile(_ profile: ConnectionProfile, password: String) {
        profiles.append(profile)
        KeychainManager.savePassword(password, for: profile.id)
        save()
    }

    func deleteProfile(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        KeychainManager.deletePassword(for: profile.id)
        connections[profile.id] = nil
        connectedIDs.remove(profile.id)
        currentDatabases[profile.id] = nil
        save()
    }

    func connection(for id: UUID) -> (any DatabaseConnection)? {
        connections[id]
    }

    func connect(_ profile: ConnectionProfile) async {
        connectionErrors[profile.id] = nil
        // SQLite has no username/password at all — a file path is the
        // whole "connection." Only MySQL/Postgres need a saved Keychain
        // entry to proceed.
        let password: String
        if profile.engine.connectsToFile {
            password = ""
        } else {
            guard let saved = KeychainManager.readPassword(for: profile.id) else {
                connectionErrors[profile.id] = "No saved password for this connection."
                return
            }
            password = saved
        }
        do {
            let connection = try await driver(for: profile.engine).connect(profile: profile, password: password)
            connections[profile.id] = connection
            connectedIDs.insert(profile.id)
            currentDatabases[profile.id] = profile.database
        } catch {
            connectionErrors[profile.id] = error.localizedDescription
        }
    }

    /// Called after a successful `USE` on this connection (see
    /// AppState.selectDatabase) — nothing here talks to the database
    /// itself, this just records what the caller already switched to.
    func setCurrentDatabase(_ database: String, for profileID: UUID) {
        currentDatabases[profileID] = database
    }

    func disconnect(_ profile: ConnectionProfile) async {
        if let connection = connections[profile.id] {
            await connection.close()
        }
        connections[profile.id] = nil
        connectedIDs.remove(profile.id)
        currentDatabases[profile.id] = nil
    }

    /// The socket died under us (server restart, network drop) — drop the
    /// dead connection so the sidebar's status dot reflects reality and the
    /// next query attempt reconnects fresh instead of repeatedly failing
    /// against a closed connection.
    func markDisconnected(_ profileID: UUID) {
        connections[profileID] = nil
        connectedIDs.remove(profileID)
        currentDatabases[profileID] = nil
    }

    func testConnection(_ profile: ConnectionProfile, password: String) async -> Result<Void, Error> {
        do {
            let connection = try await driver(for: profile.engine).connect(profile: profile, password: password)
            await connection.close()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        profiles = (try? JSONDecoder().decode([ConnectionProfile].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
