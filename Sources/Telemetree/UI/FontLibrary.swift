import AppKit
import CoreText

/// Bundled Geist / Geist Mono fonts, registered at runtime since this is a
/// plain SPM executable (no Info.plist font declarations to rely on). Falls
/// back to the system font if a weight isn't bundled or registration fails.
enum FontLibrary {
    private static let registerOnce: Void = {
        for name in ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "Geist-Bold", "GeistMono-Regular", "GeistMono-Medium"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        _ = registerOnce
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Geist-Bold"
        case .semibold: name = "Geist-SemiBold"
        case .medium: name = "Geist-Medium"
        default: name = "Geist-Regular"
        }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        _ = registerOnce
        let name = (weight == .regular) ? "GeistMono-Regular" : "GeistMono-Medium"
        return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
