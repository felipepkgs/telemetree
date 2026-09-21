import Foundation

/// A reusable piece of SQL, distinct from a QueryDocument: snippets
/// represent canned SQL to insert into whatever you're working on, not
/// ongoing work themselves. Variables are plain literal text like
/// `{{email}}` — no templating engine, the user edits them in place after
/// insertion.
struct Snippet: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sql: String = ""
    var folderID: UUID?
    var sortOrder: Int = 0
    var labelColor: LabelColor?
}
