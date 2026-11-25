import AppKit

// Draws the app icon (yellow note with a folded corner) at all macOS icon sizes.
// Usage: swift scripts/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
let outDir = CommandLine.arguments[1]
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let card = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = s * 0.18
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012); shadow.set()
    let path = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.93, blue: 0.55, alpha: 1), NSColor(srgbRed: 1, green: 0.84, blue: 0.30, alpha: 1)])!
        .draw(in: path, angle: -90)
    NSShadow().set()
    NSColor.black.withAlphaComponent(0.28).setFill()
    for i in 0..<3 {   // text lines
        let y = card.maxY - s * (0.30 + 0.14 * CGFloat(i))
        let w = card.width * (i == 2 ? 0.45 : 0.65)
        NSBezierPath(roundedRect: NSRect(x: card.minX + s * 0.12, y: y, width: w, height: s * 0.035),
                     xRadius: s * 0.0175, yRadius: s * 0.0175).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let entries: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [String] = []
for (pt, scale) in entries {
    let name = "icon_\(pt)x\(pt)@\(scale)x.png"
    try! render(pt * scale).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    images.append("{\"size\":\"\(pt)x\(pt)\",\"idiom\":\"mac\",\"filename\":\"\(name)\",\"scale\":\"\(scale)x\"}")
}
let json = "{\"images\":[\(images.joined(separator: ","))],\"info\":{\"version\":1,\"author\":\"xcode\"}}"
try! json.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
