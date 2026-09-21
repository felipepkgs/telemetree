import AppKit
import Combine

@MainActor
final class SQLEditorViewController: NSViewController {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()

    init(appState: AppState) {
        self.appState = appState
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
        setupUI()
        bind()
    }

    private func setupUI() {
        runButton.bezelStyle = .rounded
        runButton.target = self
        runButton.action = #selector(run)
        runButton.keyEquivalent = "\r"
        runButton.keyEquivalentModifierMask = [.command]
        runButton.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .boldSystemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(titleLabel)
        toolbar.addSubview(progressIndicator)
        toolbar.addSubview(runButton)

        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.delegate = self
        textView.string = appState.sqlText
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(toolbar)
        view.addSubview(divider)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            runButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            runButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            progressIndicator.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -8),
            progressIndicator.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            divider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bind() {
        appState.$selectedProfileID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHeader() }
            .store(in: &cancellables)

        appState.connectionManager.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHeader() }
            .store(in: &cancellables)

        appState.$isExecuting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] executing in
                guard let self else { return }
                self.updateHeader()
                executing ? self.progressIndicator.startAnimation(nil) : self.progressIndicator.stopAnimation(nil)
            }
            .store(in: &cancellables)

        appState.$sqlText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, self.textView.string != text else { return }
                self.textView.string = text
            }
            .store(in: &cancellables)
    }

    private func updateHeader() {
        titleLabel.stringValue = appState.selectedProfile?.name ?? "No connection selected"
        runButton.isEnabled = !appState.isExecuting && appState.selectedProfileID != nil
    }

    @objc private func run() {
        appState.executeCurrentSQL()
    }
}

extension SQLEditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        appState.sqlText = textView.string
    }
}
