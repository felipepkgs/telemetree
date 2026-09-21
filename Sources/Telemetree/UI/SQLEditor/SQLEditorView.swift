import SwiftUI

struct SQLEditorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let profile = appState.selectedProfile {
                    Text(profile.name)
                        .font(.callout.bold())
                } else {
                    Text("No connection selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appState.executeCurrentSQL()
                } label: {
                    if appState.isExecuting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Run", systemImage: "play.fill")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appState.isExecuting || appState.selectedProfileID == nil)
            }
            .padding(8)

            Divider()

            TextEditor(text: $appState.sqlText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
        }
    }
}
