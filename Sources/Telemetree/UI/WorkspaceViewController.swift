import AppKit

/// The SQL editor stacked above the results grid.
@MainActor
final class WorkspaceViewController: NSSplitViewController {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = false

        let editorVC = SQLEditorViewController(appState: appState)
        let editorItem = NSSplitViewItem(viewController: editorVC)
        editorItem.minimumThickness = 120

        let gridVC = ResultsGridViewController(appState: appState)
        let gridItem = NSSplitViewItem(viewController: gridVC)
        gridItem.minimumThickness = 120

        addSplitViewItem(editorItem)
        addSplitViewItem(gridItem)
    }
}
