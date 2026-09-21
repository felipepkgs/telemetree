import Foundation

struct ConnectionProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int = 3306
    var username: String
    var database: String
    var useSSL: Bool = false
}
