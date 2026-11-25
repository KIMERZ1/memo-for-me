import AppKit
import StickyCore

enum NoteAppearance {
    static let baseFontSize: CGFloat = 13

    static func color(for c: NoteColor) -> NSColor {
        switch c {
        case .yellow: return NSColor(srgbRed: 1.000, green: 0.953, blue: 0.722, alpha: 1)
        case .blue:   return NSColor(srgbRed: 0.839, green: 0.902, blue: 0.984, alpha: 1)
        }
    }
}

/// Solid color, optionally with an aspect-fill image under a white veil (keeps black text readable).
final class NoteBackgroundView: NSView {
    var color: NSColor = NoteAppearance.color(for: .yellow) { didSet { needsDisplay = true } }
    var image: NSImage? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        image.draw(in: NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h))
        NSColor.white.withAlphaComponent(0.55).setFill()
        bounds.fill()
    }
}
