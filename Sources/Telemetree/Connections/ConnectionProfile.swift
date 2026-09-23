import Foundation

struct ConnectionProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var engine: DatabaseEngine = .mysql
    var host: String = ""
    var port: Int = 3306
    var username: String = ""
    var database: String = ""
    var useSSL: Bool = false
    /// SQLite only — path to the .sqlite/.db file. Unused for other engines.
    var filePath: String = ""

    init(
        id: UUID = UUID(),
        name: String,
        engine: DatabaseEngine = .mysql,
        host: String = "",
        port: Int = 3306,
        username: String = "",
        database: String = "",
        useSSL: Bool = false,
        filePath: String = ""
    ) {
        self.id = id
        self.name = name
        self.engine = engine
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.useSSL = useSSL
        self.filePath = filePath
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, engine, host, port, username, database, useSSL, filePath
    }

    // Custom decoder, not relying on synthesized-default behavior for
    // missing keys: `engine` and `filePath` didn't exist in
    // connections.json before this app supported more than MySQL, and a
    // saved-profile decode failure here previously caused a real
    // crash-on-launch bug (see SPEC.md) — every new/renamed field here
    // gets an explicit decodeIfPresent fallback, not an assumption.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        engine = try container.decodeIfPresent(DatabaseEngine.self, forKey: .engine) ?? .mysql
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 3306
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        database = try container.decodeIfPresent(String.self, forKey: .database) ?? ""
        useSSL = try container.decodeIfPresent(Bool.self, forKey: .useSSL) ?? false
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath) ?? ""
    }
}
