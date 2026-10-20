import AppKit
import Combine

/// The tab bar, SQL editor, and results grid for the active connection's
/// query workspace.
@MainActor
final class WorkspaceViewController: NSViewController {
    private let appState: AppState
    private let tabBar: DocumentTabBarView
    private let statusBar: WorkspaceStatusBarView
    private let splitViewController = NSSplitViewController()
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        self.tabBar = DocumentTabBarView(appState: appState)
        self.statusBar = WorkspaceStatusBarView(appState: appState)
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

        appState.themeStore.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in
                self?.view.layer?.backgroundColor = theme.palette.window.cgColor
                self?.tabBar.layer?.backgroundColor = theme.palette.window.cgColor
                self?.splitViewController.view.layer?.backgroundColor = theme.palette.editor.cgColor
            }
            .store(in: &cancellables)
        view.wantsLayer = true
        tabBar.wantsLayer = true
        splitViewController.view.wantsLayer = true

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
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        let splitContainerView = splitViewController.view
        splitContainerView.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBar)
        view.addSubview(divider)
        view.addSubview(splitContainerView)
        view.addSubview(statusBar)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 32),

            divider.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            splitContainerView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            splitContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitContainerView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
}
