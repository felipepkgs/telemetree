import Foundation

@MainActor
final class SyntaxThemeStore: ObservableObject {
    @Published private(set) var current: SyntaxTheme

    private let defaultsKey = "com.telemetree.app.syntaxThemeID"

    init() {
        let savedID = UserDefaults.standard.string(forKey: defaultsKey)
        current = SyntaxTheme.all.first { $0.id == savedID } ?? .default
    }

    func select(_ theme: SyntaxTheme) {
        current = theme
        UserDefaults.standard.set(theme.id, forKey: defaultsKey)
    }
}
