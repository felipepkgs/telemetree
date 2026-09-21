import AppKit
import Combine

/// Shows the open query documents as a row of tabs mirroring the sidebar's
/// open state. Tabs beyond the visible width are simply clipped for now —
/// the sidebar remains the reliable way to reach every open/closed document.
@MainActor
final class DocumentTabBarView: NSView {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private let stackView = NSStackView()

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)
        setupUI()
        bind()
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        stackView.orientation = .horizontal
        stackView.spacing = 2
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func bind() {
        Publishers.CombineLatest3(appState.$openDocumentIDs, appState.$activeDocumentID, appState.queryStore.$documents)
            .combineLatest(appState.themeStore.$current)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.rebuild() }
            .store(in: &cancellables)
    }

    private func rebuild() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let theme = appState.themeStore.current
        for documentID in appState.openDocumentIDs {
            let title = appState.queryStore.document(id: documentID)?.name ?? "Untitled"
            let isActive = documentID == appState.activeDocumentID
            let tab = TabButtonView(
                title: title,
                isActive: isActive,
                theme: theme,
                onSelect: { [weak appState] in appState?.activate(documentID) },
                onClose: { [weak appState] in appState?.closeDocument(documentID) }
            )
            stackView.addArrangedSubview(tab)
        }
    }
}
