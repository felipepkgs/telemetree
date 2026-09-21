import AppKit

/// The tab bar, SQL editor, and results grid for the active connection's
/// query workspace.
@MainActor
final class WorkspaceViewController: NSViewController {
    private let appState: AppState
    private let tabBar: DocumentTabBarView
    private let splitViewController = NSSplitViewController()

    init(appState: AppState) {
        self.appState = appState
        self.tabBar = DocumentTabBarView(appState: appState)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitViewController.splitView.isVertical = false

        let editorVC = SQLEditorViewController(appState: appState)
        let editorItem = NSSplitViewItem(viewController: editorVC)
        editorItem.minimumThickness = 120

        let gridVC = ResultsGridViewController(appState: appState)
        let gridItem = NSSplitViewItem(viewController: gridVC)
        gridItem.minimumThickness = 120

        splitViewController.addSplitViewItem(editorItem)
        splitViewController.addSplitViewItem(gridItem)
        addChild(splitViewController)

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        let splitContainerView = splitViewController.view
        splitContainerView.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBar)
        view.addSubview(divider)
        view.addSubview(splitContainerView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 30),

            divider.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            splitContainerView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            splitContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
