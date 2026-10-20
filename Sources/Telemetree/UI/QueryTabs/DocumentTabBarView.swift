import AppKit
import Combine

@MainActor
final class DocumentTabBarView: NSView {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private let stackView = NSStackView()

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)
        stackView.orientation = .horizontal
        stackView.spacing = 3
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        Publishers.CombineLatest3(appState.$openDocumentIDs, appState.$activeDocumentID, appState.queryStore.$documents)
            .combineLatest(appState.themeStore.$current)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.rebuild() }
            .store(in: &cancellables)
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuild() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let theme = appState.themeStore.current
        for documentID in appState.openDocumentIDs {
            let tab = TabButtonView(
                title: appState.queryStore.document(id: documentID)?.name ?? "Untitled",
                isActive: documentID == appState.activeDocumentID,
                theme: theme,
                onSelect: { [weak appState] in appState?.activate(documentID) },
                onClose: { [weak appState] in appState?.closeDocument(documentID) }
            )
            stackView.addArrangedSubview(tab)
        }
    }
}
