import AppKit

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var current: Theme

    private let defaultsKey = "com.telemetree.app.themeID"

    init() {
        let savedID = UserDefaults.standard.string(forKey: defaultsKey)
        current = Theme.all.first { $0.id == savedID } ?? .dark
        NSApp.appearance = NSAppearance(named: current.appearanceName)
    }

    func select(_ theme: Theme) {
        current = theme
        UserDefaults.standard.set(theme.id, forKey: defaultsKey)
        NSApp.appearance = NSAppearance(named: theme.appearanceName)
    }
}
