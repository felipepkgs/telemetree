import Foundation

/// Owns saved connection profiles and the currently-open connections.
/// Profile metadata is persisted as JSON in Application Support; passwords
/// live only in the Keychain (see KeychainManager).
@MainActor
final class ConnectionManager: ObservableObject {
    @Published private(set) var profiles: [ConnectionProfile] = []
    @Published private(set) var connectedIDs: Set<UUID> = []
    @Published var connectionErrors: [UUID: String] = [:]

    private var connections: [UUID: any DatabaseConnection] = [:]
    private let driver: any DatabaseDriver = MySQLDriver()
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
        save()
    }

    func connection(for id: UUID) -> (any DatabaseConnection)? {
        connections[id]
    }

    func connect(_ profile: ConnectionProfile) async {
        connectionErrors[profile.id] = nil
        guard let password = KeychainManager.readPassword(for: profile.id) else {
            connectionErrors[profile.id] = "No saved password for this connection."
            return
        }
        do {
            let connection = try await driver.connect(profile: profile, password: password)
            connections[profile.id] = connection
            connectedIDs.insert(profile.id)
        } catch {
            connectionErrors[profile.id] = error.localizedDescription
        }
    }

    func disconnect(_ profile: ConnectionProfile) async {
        if let connection = connections[profile.id] {
            await connection.close()
        }
        connections[profile.id] = nil
        connectedIDs.remove(profile.id)
    }

    /// The socket died under us (server restart, network drop) — drop the
    /// dead connection so the sidebar's status dot reflects reality and the
    /// next query attempt reconnects fresh instead of repeatedly failing
    /// against a closed connection.
    func markDisconnected(_ profileID: UUID) {
        connections[profileID] = nil
        connectedIDs.remove(profileID)
    }

    func testConnection(_ profile: ConnectionProfile, password: String) async -> Result<Void, Error> {
        do {
            let connection = try await driver.connect(profile: profile, password: password)
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
