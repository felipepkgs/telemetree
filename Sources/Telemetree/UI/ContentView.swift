import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VSplitView {
                SQLEditorView()
                    .frame(minHeight: 150)
                ResultsGridView()
                    .frame(minHeight: 150)
            }
        }
    }
}
