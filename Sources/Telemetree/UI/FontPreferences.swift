import AppKit

enum EditorFontChoice: String, CaseIterable {
    case geistMono = "Geist Mono"
    case sfMono = "SF Mono"
    case menlo = "Menlo"

    func font(size: CGFloat) -> NSFont {
        switch self {
        case .geistMono:
            return FontLibrary.mono(size)
        case .sfMono:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo:
            return NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

/// Editor font choice/size — separate from FontLibrary, which just
/// handles loading/registering the bundled fonts. This is the user's
/// preference on top of that.
@MainActor
final class FontPreferencesStore: ObservableObject {
    @Published private(set) var choice: EditorFontChoice
    @Published private(set) var size: CGFloat

    private let choiceKey = "com.telemetree.app.editorFontChoice"
    private let sizeKey = "com.telemetree.app.editorFontSize"

    static let sizeRange: [CGFloat] = [10, 11, 12, 13, 14, 16, 18]

    init() {
        let defaults = UserDefaults.standard
        choice = EditorFontChoice(rawValue: defaults.string(forKey: choiceKey) ?? "") ?? .geistMono
        let savedSize = defaults.double(forKey: sizeKey)
        size = savedSize > 0 ? CGFloat(savedSize) : 12
    }

    var font: NSFont { choice.font(size: size) }

    func setChoice(_ choice: EditorFontChoice) {
        self.choice = choice
        UserDefaults.standard.set(choice.rawValue, forKey: choiceKey)
    }

    func setSize(_ size: CGFloat) {
        self.size = size
        UserDefaults.standard.set(Double(size), forKey: sizeKey)
    }
}
