import SwiftUI

struct ConnectionRow: View {
    @EnvironmentObject var appState: AppState
    let profile: ConnectionProfile

    @State private var databases: [String] = []
    @State private var isExpanded = false

    private var isConnected: Bool {
        appState.connectionManager.connectedIDs.contains(profile.id)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isConnected {
                ForEach(databases, id: \.self) { database in
                    DatabaseRow(profile: profile, database: database)
                }
            } else if let error = appState.connectionManager.connectionErrors[profile.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } label: {
            HStack {
                Circle()
                    .fill(isConnected ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(profile.name)
                    .fontWeight(appState.selectedProfileID == profile.id ? .semibold : .regular)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appState.selectedProfileID = profile.id
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded else { return }
            Task {
                if !isConnected {
                    await appState.connectionManager.connect(profile)
                }
                if isConnected {
                    appState.selectedProfileID = profile.id
                    await loadDatabases()
                }
            }
        }
    }

    private func loadDatabases() async {
        guard let connection = appState.connectionManager.connection(for: profile.id) else { return }
        let systemDatabases: Set<String> = ["information_schema", "performance_schema", "mysql", "sys"]
        databases = (try? await connection.listDatabases())?.filter { !systemDatabases.contains($0) } ?? []
    }
}
