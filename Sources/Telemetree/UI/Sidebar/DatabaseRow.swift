import SwiftUI

struct DatabaseRow: View {
    @EnvironmentObject var appState: AppState
    let profile: ConnectionProfile
    let database: String

    @State private var tables: [DatabaseTable] = []
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(database, isExpanded: $isExpanded) {
            ForEach(tables) { table in
                Label(table.name, systemImage: "tablecells")
                    .font(.callout)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectedProfileID = profile.id
                        appState.runQuery("SELECT * FROM `\(database)`.`\(table.name)` LIMIT 100;")
                    }
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded, tables.isEmpty else { return }
            Task {
                guard let connection = appState.connectionManager.connection(for: profile.id) else { return }
                tables = (try? await connection.listTables(inDatabase: database)) ?? []
            }
        }
    }
}
