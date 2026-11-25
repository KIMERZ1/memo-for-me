import AppKit

struct FormatBarActions {
    var onBold: () -> Void = {}
    var onItalic: () -> Void = {}
    var onUnderline: () -> Void = {}
    var onStrike: () -> Void = {}
}

/// Which of B / I / U / S the selection already has.
struct FormatBarStyle: Equatable {
    var bold = false, italic = false, underline = false, strike = false
}

/// One of B / I / U / S: soft shading under the pointer, stronger while the style is switched on.
/// Plain AppKit with an always-active tracking area: the bar lives in a window that never becomes key while
/// the app is inactive, where SwiftUI's hover callbacks do not fire reliably.
private final class FormatButton: NSView {
    private let label: NSAttributedString
    private let action: () -> Void
    var isOn = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }

    init(label: NSAttributedString, action: @escaping () -> Void) {
        self.label = label
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 24))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false }
    override func mouseMoved(with event: NSEvent) { NSCursor.arrow.set() }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func mouseDown(with event: NSEvent) { pressing = true }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressing = false
        if inside { action() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let shade: CGFloat = pressing ? 0.24 : (isOn ? (hovering ? 0.22 : 0.14) : (hovering ? 0.10 : 0))
        if shade > 0 {
            NSColor.black.withAlphaComponent(shade).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let size = label.size()
        label.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

/// The white pill that floats under highlighted text:  B  I  U  S
final class FormatBarView: NSView {
    static let margin: CGFloat = 10                          // room for the shadow
    static let cardSize = NSSize(width: 142, height: 36)
    static let size = NSSize(width: cardSize.width + 2 * margin, height: cardSize.height + 2 * margin)

    private let card = NSView()
    private var buttons: [FormatButton] = []
    var actions = FormatBarActions()

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        card.frame = NSRect(x: Self.margin, y: Self.margin, width: Self.cardSize.width, height: Self.cardSize.height)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.22
        card.layer?.shadowRadius = 7
        card.layer?.shadowOffset = CGSize(width: 0, height: -3)
        addSubview(card)

        func text(_ s: String, _ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
            var a = attrs
            a[.foregroundColor] = NSColor.black.withAlphaComponent(0.85)
            return NSAttributedString(string: s, attributes: a)
        }
        let regular = NSFont.systemFont(ofSize: 14)
        let specs: [(NSAttributedString, () -> Void)] = [
            (text("B", [.font: NSFont.systemFont(ofSize: 14, weight: .bold)]), { [unowned self] in self.actions.onBold() }),
            (text("I", [.font: regular, .obliqueness: 0.2]), { [unowned self] in self.actions.onItalic() }),
            (text("U", [.font: regular, .underlineStyle: NSUnderlineStyle.single.rawValue]), { [unowned self] in self.actions.onUnderline() }),
            (text("S", [.font: regular, .strikethroughStyle: NSUnderlineStyle.single.rawValue]), { [unowned self] in self.actions.onStrike() }),
        ]
        for (i, spec) in specs.enumerated() {
            let b = FormatButton(label: spec.0, action: spec.1)
            b.frame.origin = NSPoint(x: 10 + CGFloat(i) * 32, y: 6)
            card.addSubview(b)
            buttons.append(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ style: FormatBarStyle) {
        buttons[0].isOn = style.bold; buttons[1].isOn = style.italic
        buttons[2].isOn = style.underline; buttons[3].isOn = style.strike
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) { NSCursor.arrow.set() }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

/// The floating bar lives in its own small window above the note, so the note's text view (and its I-beam
/// cursor) has no say over the cursor on the bar.
@MainActor
final class FormatBarWindow {
    private let panel: NSPanel
    let view = FormatBarView(frame: .zero)
    private weak var parent: NSWindow?
    private var isShown = false

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: FormatBarView.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                 // the bar draws its own shadow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
    }

    /// Shows the bar centered under `selection` (screen coordinates), or above it when there is no room below.
    func show(below selection: NSRect, over parent: NSWindow) {
        let size = FormatBarView.size
        let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var y = selection.minY - size.height
        if y < screen.minY { y = selection.maxY }
        let x = min(max(screen.minX, selection.midX - size.width / 2), screen.maxX - size.width)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        guard !isShown else { return }          // only the first call orders the window in
        self.parent?.removeChildWindow(panel)
        parent.addChildWindow(panel, ordered: .above)
        self.parent = parent
        panel.orderFront(nil)
        isShown = true
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        parent?.removeChildWindow(panel)
        parent = nil
        panel.orderOut(nil)
    }
}
