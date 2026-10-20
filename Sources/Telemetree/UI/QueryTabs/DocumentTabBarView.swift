import AppKit
import Combine

@MainActor
final class DocumentTabBarView: NSView {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)
        stackView.orientation = .horizontal
        stackView.spacing = 3
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .horizontal)
        scrollView.documentView = stackView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor)
        ])
        Publishers.CombineLatest4(
            appState.$openDocumentIDs,
            appState.$activeDocumentID,
            appState.queryStore.$documents,
            appState.queryStore.$temporaryDocuments
        )
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
        wantsLayer = true
        layer?.backgroundColor = theme.palette.window.cgColor
        scrollView.backgroundColor = theme.palette.window
        for documentID in appState.openDocumentIDs {
            let document = appState.queryStore.document(id: documentID)
            let tab = TabButtonView(
                title: document?.name ?? "Untitled",
                isActive: documentID == appState.activeDocumentID,
                theme: theme,
                onSelect: { [weak appState] in appState?.activate(documentID) },
                onClose: { [weak appState] in appState?.closeDocument(documentID) }
            )
            stackView.addArrangedSubview(tab)
            if documentID == appState.activeDocumentID {
                DispatchQueue.main.async { [weak self, weak tab] in
                    guard let self, let tab else { return }
                    self.layoutSubtreeIfNeeded()
                    self.scrollView.contentView.scrollToVisible(tab.frame)
                    self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
                }
            }
        }
    }
}
