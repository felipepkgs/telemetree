import Foundation

/// Replaces the SPM-generated `Bundle.module` accessor, which crashes
/// with an uncatchable `fatalError` when its one hardcoded candidate path
/// doesn't match how the binary was actually built and packaged.
///
/// Confirmed via a real crash (felipepkgs/telemetree#2, IPS report): the
/// generated accessor only checks `Bundle.main.bundleURL` (the .app's own
/// root) plus the CI build directory — never `Contents/Resources`, which
/// is where `Scripts/build_app.sh` actually puts the resource bundle in a
/// real .app. That mismatch is invisible in local `swift run` testing
/// (where the "bundle" is just a build-output directory next to the
/// executable) and only crashes a real packaged, installed app — exactly
/// why it shipped.
enum TelemetreeResources {
    private static let bundleName = "Telemetree_Telemetree.bundle"

    static func url(forResource name: String, withExtension ext: String, subdirectory: String) -> URL? {
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        let layouts = [bundleName, "\(bundleName)/Contents/Resources"]

        for base in bases {
            for layout in layouts {
                let candidate = base
                    .appendingPathComponent(layout)
                    .appendingPathComponent(subdirectory)
                    .appendingPathComponent(name)
                    .appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}
