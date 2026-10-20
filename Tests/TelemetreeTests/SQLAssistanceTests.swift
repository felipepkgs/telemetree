import XCTest
@testable import Telemetree

final class SQLAssistanceTests: XCTestCase {
    func testQuotedTableAndAliasResolveWithinStatement() async {
        let sql = "SELECT u.email FROM \"user records\" AS u; SELECT p.id FROM payments p"
        await MainActor.run {
            XCTAssertEqual(SQLCompletionController.tableReferences(in: sql).map(\.name), ["user records", "payments"])
            XCTAssertEqual(SQLCompletionController.tableAliases(in: sql, at: 10)["u"], "user records")
            XCTAssertNil(SQLCompletionController.tableAliases(in: sql, at: (sql as NSString).length)["u"])
        }
    }

    func testFormatterPreservesMySQLCommentsAndLiterals() {
        let sql = "select '-- not a comment' as value # keep this comment\nfrom users"
        let formatted = SQLFormatter.format(sql, dialect: .mysql)
        XCTAssertTrue(formatted.contains("'-- not a comment'"))
        XCTAssertTrue(formatted.contains("# keep this comment\n"))
        XCTAssertTrue(formatted.contains("FROM users"))
    }

    func testFormatterPreservesPostgresDollarQuotedBody() {
        let sql = "select $body$select x; from y$body$ as value from records"
        let formatted = SQLFormatter.format(sql, dialect: .postgres)
        XCTAssertTrue(formatted.contains("$body$select x; from y$body$"))
        XCTAssertTrue(formatted.contains("FROM records"))
    }

    func testDollarQuotedSemicolonDoesNotSplitStatement() {
        let sql = "SELECT $body$DELETE FROM users; SELECT 1$body$; SELECT 2;"
        XCTAssertEqual(SQLStatementLocator.statements(in: sql).count, 2)
    }

    func testTemporaryQueryIsOnlyPersistedAfterExplicitSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queries.json")

        let documentID = await MainActor.run { () -> UUID in
            let store = QueryStore(storeURL: url)
            let document = store.createTemporaryDocument(name: "Browse · users")
            store.updateSQL(document.id, sql: "SELECT * FROM users")
            XCTAssertTrue(store.isTemporaryDocument(document.id))
            store.delete(document.id)
            XCTAssertNil(store.document(id: document.id))
            let saved = store.createTemporaryDocument(name: "Browse · users")
            store.updateSQL(saved.id, sql: "SELECT * FROM users")
            store.saveTemporaryDocument(saved.id, name: "Users", folderID: nil)
            return saved.id
        }

        try await Task.sleep(for: .milliseconds(500))
        let reopened = await MainActor.run { QueryStore(storeURL: url) }
        await MainActor.run {
            XCTAssertFalse(reopened.isTemporaryDocument(documentID))
            XCTAssertEqual(reopened.document(id: documentID)?.sql, "SELECT * FROM users")
        }
    }
}
