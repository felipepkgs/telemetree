import Foundation

struct QueryFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID?
    var sortOrder: Int = 0
}
