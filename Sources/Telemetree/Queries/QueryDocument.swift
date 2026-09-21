import Foundation

struct QueryDocument: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sql: String = ""
    var connectionProfileID: UUID?
    var folderID: UUID?
    var sortOrder: Int = 0
    var updatedAt: Date = Date()
    var labelColor: LabelColor?
}
