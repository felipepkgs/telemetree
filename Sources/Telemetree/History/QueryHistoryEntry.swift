import Foundation

struct QueryHistoryEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var sql: String
    var connectionProfileID: UUID?
    var connectionName: String
    var timestamp: Date = Date()
    var succeeded: Bool
    var errorMessage: String?
}
