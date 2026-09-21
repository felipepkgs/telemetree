import AppKit

/// The crossed 45°/-45° diagonal weave from the Carbon Fiber theme's
/// source spec, baked into a small tile and used as an NSColor pattern —
/// this is what makes Vapor Carbon's bars read as actual carbon fiber
/// instead of just a dark tint.
enum CarbonWeaveTexture {
    static func patternColor(base: NSColor) -> NSColor {
        let tileSize: CGFloat = 6
        let image = NSImage(size: NSSize(width: tileSize, height: tileSize))
        image.lockFocus()

        base.setFill()
        NSRect(x: 0, y: 0, width: tileSize, height: tileSize).fill()

        let lightDiagonal = NSBezierPath()
        lightDiagonal.move(to: NSPoint(x: 0, y: 0))
        lightDiagonal.line(to: NSPoint(x: tileSize, y: tileSize))
        lightDiagonal.lineWidth = 1
        NSColor.white.withAlphaComponent(0.07).setStroke()
        lightDiagonal.stroke()

        let darkDiagonal = NSBezierPath()
        darkDiagonal.move(to: NSPoint(x: 0, y: tileSize))
        darkDiagonal.line(to: NSPoint(x: tileSize, y: 0))
        darkDiagonal.lineWidth = 1
        NSColor.black.withAlphaComponent(0.22).setStroke()
        darkDiagonal.stroke()

        image.unlockFocus()
        return NSColor(patternImage: image)
    }
}
