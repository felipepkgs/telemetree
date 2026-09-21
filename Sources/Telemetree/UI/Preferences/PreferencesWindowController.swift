import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let appState: AppState
    private let tabView = NSTabView()

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
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

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(makeAppearanceTab())
        tabView.addTabViewItem(makeSyntaxTab())
        tabView.addTabViewItem(makeEditorTab())

        contentView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    // MARK: - Tabs

    private func makeAppearanceTab() -> NSTabViewItem {
        let themePopup = NSPopUpButton()
        for theme in Theme.all {
            themePopup.addItem(withTitle: theme.name)
        }
        themePopup.selectItem(withTitle: appState.themeStore.current.name)
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))

        let grid = NSGridView(views: [[label("Theme:"), themePopup]])
        return tabItem(identifier: "appearance", label: "Appearance", grid: grid)
    }

    private func makeSyntaxTab() -> NSTabViewItem {
        let syntaxPopup = NSPopUpButton()
        for theme in SyntaxTheme.all {
            syntaxPopup.addItem(withTitle: theme.name)
        }
        syntaxPopup.selectItem(withTitle: appState.syntaxThemeStore.current.name)
        syntaxPopup.target = self
        syntaxPopup.action = #selector(syntaxThemeChanged(_:))

        let grid = NSGridView(views: [[label("Highlighting:"), syntaxPopup]])
        return tabItem(identifier: "syntax", label: "Syntax Highlighting", grid: grid)
    }

    private func makeEditorTab() -> NSTabViewItem {
        let fontPopup = NSPopUpButton()
        for choice in EditorFontChoice.allCases {
            fontPopup.addItem(withTitle: choice.rawValue)
        }
        fontPopup.selectItem(withTitle: appState.fontPreferences.choice.rawValue)
        fontPopup.target = self
        fontPopup.action = #selector(fontChoiceChanged(_:))

        let sizePopup = NSPopUpButton()
        for size in FontPreferencesStore.sizeRange {
            sizePopup.addItem(withTitle: "\(Int(size)) pt")
        }
        sizePopup.selectItem(withTitle: "\(Int(appState.fontPreferences.size)) pt")
        sizePopup.target = self
        sizePopup.action = #selector(fontSizeChanged(_:))

        let grid = NSGridView(views: [
            [label("Font:"), fontPopup],
            [label("Size:"), sizePopup]
        ])
        return tabItem(identifier: "editor", label: "Editor", grid: grid)
    }

    // MARK: - Helpers

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func tabItem(identifier: String, label labelText: String, grid: NSGridView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: identifier)
        item.label = labelText

        grid.rowSpacing = 12
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 180
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor, constant: 10),
            grid.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        item.view = container
        return item
    }

    // MARK: - Actions

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title,
              let theme = Theme.all.first(where: { $0.name == title }) else { return }
        appState.themeStore.select(theme)
    }

    @objc private func syntaxThemeChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title,
              let theme = SyntaxTheme.all.first(where: { $0.name == title }) else { return }
        appState.syntaxThemeStore.select(theme)
    }

    @objc private func fontChoiceChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title,
              let choice = EditorFontChoice(rawValue: title) else { return }
        appState.fontPreferences.setChoice(choice)
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        guard let index = sender.indexOfSelectedItem as Int?,
              index >= 0, index < FontPreferencesStore.sizeRange.count else { return }
        appState.fontPreferences.setSize(FontPreferencesStore.sizeRange[index])
    }
}
