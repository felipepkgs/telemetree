import Foundation

/// Runtime (non-persisted) editing/execution state for one open query
/// document. The document's name/SQL/connection are persisted via
/// QueryStore; this just holds what's currently on screen for it.
@MainActor
final class OpenDocumentState: ObservableObject {
    let documentID: UUID

    @Published var sql: String
    @Published var connectionProfileID: UUID?
    @Published var queryResult: QueryResult = .empty
    @Published var isExecuting = false
    @Published var errorMessage: String?

    /// Set only for a plain, un-LIMITed SELECT — lets "Load More" fetch the
    /// next page of the same statement instead of the whole result set.
    var paginationBaseSQL: String?
    var paginationOffset = 0
    @Published var hasMorePages = false

    init(document: QueryDocument) {
        self.documentID = document.id
        self.sql = document.sql
        self.connectionProfileID = document.connectionProfileID
    }
}
