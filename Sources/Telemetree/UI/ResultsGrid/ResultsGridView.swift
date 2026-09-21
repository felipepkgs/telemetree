import SwiftUI
import AppKit

struct ResultsGridView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isExecuting {
            ProgressView("Running…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = appState.errorMessage {
            ScrollView {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if appState.queryResult.columns.isEmpty {
            Text(statusText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private var statusText: String {
        if let affected = appState.queryResult.affectedRows {
            return "\(affected) row(s) affected"
        }
        return "No results"
    }

    private var statusBar: some View {
        HStack {
            Text("\(appState.queryResult.rows.count) row(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                copyAllResults()
            } label: {
                Label("Copy Results", systemImage: "doc.on.doc")
            }
            .disabled(appState.queryResult.rows.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 120, maximum: 400), spacing: 0),
            count: appState.queryResult.columns.count
        )
    }

    private var grid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(appState.queryResult.columns, id: \.self) { column in
                    Text(column)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                }

                ForEach(Array(appState.queryResult.rows.enumerated()), id: \.offset) { rowIndex, row in
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        Text(value.displayString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(value.isNull ? .secondary : .primary)
                            .italic(value.isNull)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.06))
                            .help(value.displayString)
                            .contextMenu {
                                Button("Copy Cell") { copy(value.displayString) }
                                Button("Copy Row") { copy(rowText(row)) }
                            }
                    }
                }
            }
        }
    }

    private func rowText(_ row: [QueryValue]) -> String {
        row.map(\.displayString).joined(separator: "\t")
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func copyAllResults() {
        var lines = [appState.queryResult.columns.joined(separator: "\t")]
        lines += appState.queryResult.rows.map(rowText)
        copy(lines.joined(separator: "\n"))
    }
}
