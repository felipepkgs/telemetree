import Foundation

struct SnippetFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID?
    var sortOrder: Int = 0
}
