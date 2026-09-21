import SwiftUI

struct NewConnectionSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var host = "127.0.0.1"
    @State private var port = "3306"
    @State private var username = "root"
    @State private var password = ""
    @State private var database = ""
    @State private var useSSL = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Host", text: $host)
            TextField("Port", text: $port)
            TextField("Username", text: $username)
            SecureField("Password", text: $password)
            TextField("Database", text: $database)
            Toggle("Use SSL", isOn: $useSSL)

            if let testResult {
                Text(testResult)
                    .font(.callout)
                    .foregroundStyle(testResult.hasPrefix("Success") ? .green : .red)
            }

            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(isTesting || host.isEmpty || username.isEmpty)

                if isTesting {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding()
        .frame(minWidth: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.isEmpty || host.isEmpty || username.isEmpty)
            }
        }
    }

    private func makeProfile() -> ConnectionProfile {
        ConnectionProfile(
            name: name,
            host: host,
            port: Int(port) ?? 3306,
            username: username,
            database: database,
            useSSL: useSSL
        )
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let profile = makeProfile()
        Task {
            let result = await appState.connectionManager.testConnection(profile, password: password)
            switch result {
            case .success:
                testResult = "Success"
            case .failure(let error):
                testResult = "Failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    private func save() {
        appState.connectionManager.addProfile(makeProfile(), password: password)
        dismiss()
    }
}
