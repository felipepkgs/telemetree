import Foundation

@MainActor
final class AppState: ObservableObject {
    let connectionManager = ConnectionManager()

    @Published var selectedProfileID: UUID?
    @Published var sqlText: String = "SELECT 1;"
    @Published var queryResult: QueryResult = .empty
    @Published var isExecuting: Bool = false
    @Published var errorMessage: String?

    var selectedProfile: ConnectionProfile? {
        guard let id = selectedProfileID else { return nil }
        return connectionManager.profiles.first { $0.id == id }
    }

    func runQuery(_ sql: String) {
        sqlText = sql
        executeCurrentSQL()
    }

    func executeCurrentSQL() {
        let sql = sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return }
        guard let profileID = selectedProfileID,
              let connection = connectionManager.connection(for: profileID) else {
            errorMessage = "No active connection. Connect to a database first."
            return
        }

        isExecuting = true
        errorMessage = nil

        Task {
            do {
                queryResult = try await connection.execute(sql: sql)
            } catch {
                errorMessage = error.localizedDescription
            }
            isExecuting = false
        }
    }
}
