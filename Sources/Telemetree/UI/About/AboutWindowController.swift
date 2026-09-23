import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Telemetree"
        window.isRestorable = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let icon = NSImageView(image: NSApp.applicationIconImage ?? AppIcon.database.image)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "Telemetree")
        nameLabel.font = FontLibrary.sans(16, weight: .bold)

        let versionString = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1"
        let versionLabel = NSTextField(labelWithString: "Version \(versionString)")
        versionLabel.font = FontLibrary.sans(11)
        versionLabel.textColor = .secondaryLabelColor

        let creditsLabel = NSTextField(wrappingLabelWithString: "Icons by Icons8")
        creditsLabel.font = FontLibrary.sans(11)
        creditsLabel.alignment = .center

        let linkButton = NSButton(title: "icons8.com", target: self, action: #selector(openIcons8))
        linkButton.bezelStyle = .inline
        linkButton.isBordered = false
        linkButton.contentTintColor = .linkColor
        linkButton.font = FontLibrary.sans(11)

        let submitIssueButton = NSButton(title: "Submit an Issue…", target: self, action: #selector(openSubmitIssue))
        submitIssueButton.bezelStyle = .rounded

        let stack = NSStackView(views: [icon, nameLabel, versionLabel, creditsLabel, linkButton, submitIssueButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(14, after: linkButton)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),

            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @objc private func openIcons8() {
        if let url = URL(string: "https://icons8.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSubmitIssue() {
        if let url = URL(string: "https://github.com/felipepkgs/telemetree/issues/new") {
            NSWorkspace.shared.open(url)
        }
    }
}
