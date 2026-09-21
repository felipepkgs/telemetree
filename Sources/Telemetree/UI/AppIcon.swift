import AppKit

/// Icons8 ("SF Black" style — thick strokes, reads well at small sizes)
/// glyphs, bundled locally so the app never depends on network access at
/// runtime. Attribution lives in the About window per Icons8's linkware
/// license.
enum AppIcon: String {
    case add = "plus"
    case connection = "server"
    case database = "database"
    case table = "table"
    case folder = "opened-folder"
    case document = "document"
    case snippet = "snippet"
    case warning = "error"
    case close = "multiply"
    case trash = "trash"

    /// Point size icons render at by default — the source PNGs are fetched
    /// at 100px for Retina headroom, but AppKit displays NSImage at its
    /// `.size` in points regardless of pixel resolution, so this must be
    /// set explicitly (SF Symbols do this implicitly; bitmaps don't).
    private static let defaultPointSize = NSSize(width: 16, height: 16)

    var image: NSImage {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "png", subdirectory: "Icons"),
              let image = NSImage(contentsOf: url) else {
            return NSImage()
        }
        image.size = Self.defaultPointSize
        image.isTemplate = true
        return image
    }
}
