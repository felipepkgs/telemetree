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

    /// Set only for a plain, un-LIMITed SELECT — lets the results grid page
    /// through the same statement (LIMIT/OFFSET) instead of pulling the
    /// whole result set in one shot.
    @Published var paginationBaseSQL: String?
    @Published var currentPage = 0
    /// nil while the background COUNT(*) is still in flight (or the
    /// current result isn't paginated at all).
    @Published var totalRowCount: Int?

    /// The single source table for the currently-displayed SELECT result,
    /// when EditableResultDetector could identify exactly one — nil for
    /// anything else (a JOIN, DML, a multi-statement buffer, no result
    /// yet). Drives whether the results grid offers inline cell editing.
    @Published var editableTable: String?

    init(document: QueryDocument) {
        self.documentID = document.id
        self.sql = document.sql
        self.connectionProfileID = document.connectionProfileID
    }
}
