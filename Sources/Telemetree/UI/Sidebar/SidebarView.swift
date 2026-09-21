import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingNewConnection = false

    var body: some View {
        List {
            Section("Connections") {
                ForEach(appState.connectionManager.profiles) { profile in
                    ConnectionRow(profile: profile)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewConnection = true
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewConnection) {
            NewConnectionSheet()
        }
    }
}
