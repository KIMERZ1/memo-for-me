import AppKit
import StickyCore

struct ToolbarActions {
    var onTogglePin: () -> Void = {}
    var onToggleFloat: () -> Void = {}
    var onChangeColor: (NoteColor) -> Void = { _ in }
    var onPickBackground: () -> Void = {}
    var onRemoveBackground: () -> Void = {}
    var onClose: () -> Void = {}
    var onDelete: () -> Void = {}
    var onNewNote: () -> Void = {}
    var onNameChanged: (String) -> Void = { _ in }
    var onNameCommit: () -> Void = {}
}

/// An icon in the top bar: soft shading under the pointer (stronger while switched on or pressed) and a label
/// in the bar's middle while hovered. Plain AppKit with an always-active tracking area, so it behaves the same
/// whether or not the note is the key window.
private final class BarButton: NSView {
    private let imageView = NSImageView()
    let hint: String
    private let action: () -> Void
    var onHover: ((String?) -> Void)?
    var symbol: String { didSet { updateImage() } }
    var isOn = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }

    init(symbol: String, hint: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.hint = hint; self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = NSColor.black.withAlphaComponent(0.65)
        addSubview(imageView)
        updateImage()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateImage() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: hint)?.withSymbolConfiguration(cfg)
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; onHover?(hint); NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { hovering = false; pressing = false; onHover?(nil) }
    override func mouseDown(with event: NSEvent) { pressing = true }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressing = false
        if inside { action() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let shade: CGFloat = pressing ? 0.24 : (isOn ? (hovering ? 0.20 : 0.11) : (hovering ? 0.16 : 0))
        guard shade > 0 else { return }
        NSColor.black.withAlphaComponent(shade).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}

private final class ActionMenuItem: NSMenuItem {
    var handler: () -> Void = {}
    convenience init(_ title: String, handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: "")
        self.handler = handler
        target = self
    }
    @objc private func fire() { handler() }
}

/// The bar across the top of a note (visible while the mouse is over it):
/// [✕ pin top palette trash]  [ name | hint ]  [+]
final class NoteToolbarView: NSView, NSTextFieldDelegate {
    static let height: CGFloat = 28
    var actions = ToolbarActions()

    var isPinned = false { didSet { pin.isOn = isPinned; pin.symbol = isPinned ? "pin.fill" : "pin" } }
    var floatsOnTop = false { didSet { top.isOn = floatsOnTop } }
    var hasBackgroundImage = false
    var isLocked = false { didSet { refreshNameField() } }

    private var close, pin, top, palette, trash, plus: BarButton!
    private let nameField = NSTextField()
    private let hintView = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        close = BarButton(symbol: "xmark", hint: "닫기") { [unowned self] in self.actions.onClose() }
        pin = BarButton(symbol: "pin", hint: "위치 고정") { [unowned self] in self.actions.onTogglePin() }
        top = BarButton(symbol: "arrow.up.to.line", hint: "항상 위에") { [unowned self] in self.actions.onToggleFloat() }
        palette = BarButton(symbol: "paintpalette", hint: "색 변경") { [unowned self] in self.showColorMenu() }
        trash = BarButton(symbol: "trash", hint: "삭제") { [unowned self] in self.actions.onDelete() }
        plus = BarButton(symbol: "plus", hint: "새 메모지") { [unowned self] in self.actions.onNewNote() }
        for b in [close!, pin!, top!, palette!, trash!, plus!] {
            b.onHover = { [unowned self] in self.showHint($0) }
            addSubview(b)
        }

        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.alignment = .center
        nameField.font = .systemFont(ofSize: 11, weight: .medium)
        nameField.textColor = NSColor.black.withAlphaComponent(0.75)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.cell?.isScrollable = true
        nameField.cell?.usesSingleLineMode = true
        nameField.wantsLayer = true
        nameField.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.07).cgColor
        nameField.layer?.cornerRadius = 5
        nameField.delegate = self
        addSubview(nameField)

        hintView.font = .systemFont(ofSize: 11, weight: .semibold)
        hintView.alignment = .center
        hintView.textColor = NSColor.black.withAlphaComponent(0.8)
        hintView.wantsLayer = true
        hintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
        hintView.layer?.cornerRadius = 9
        hintView.isHidden = true
        addSubview(hintView)
        refreshNameField()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Name

    /// Sets the name from storage (does not call `onNameChanged`).
    func setName(_ n: String) { if nameField.stringValue != n { nameField.stringValue = n } }
    /// The name box in this view's coordinates.
    var nameFrame: NSRect { nameField.frame }

    private func refreshNameField() {
        nameField.isEditable = !isLocked
        nameField.isSelectable = !isLocked
        nameField.placeholderString = isLocked ? "보안 메모지" : "이름"
        if isLocked { nameField.stringValue = "" }
    }

    func controlTextDidChange(_ obj: Notification) { actions.onNameChanged(nameField.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard sel == #selector(NSResponder.insertNewline(_:)) else { return false }
        actions.onNameCommit()
        return true
    }

    // MARK: Hint

    private func showHint(_ text: String?) {
        guard let text else { hintView.isHidden = true; nameField.alphaValue = 1; return }
        hintView.stringValue = text
        hintView.sizeToFit()
        let w = hintView.frame.width + 16, h: CGFloat = 18
        hintView.frame = NSRect(x: nameField.frame.midX - w / 2, y: (bounds.height - h) / 2, width: w, height: h)
        hintView.isHidden = false
        nameField.alphaValue = 0      // stays in place (and keeps editing state) but out of sight
    }

    // MARK: Color menu

    private func showColorMenu() {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("노랑") { [unowned self] in self.actions.onChangeColor(.yellow) })
        menu.addItem(ActionMenuItem("파랑") { [unowned self] in self.actions.onChangeColor(.blue) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("이미지 배경 선택…") { [unowned self] in self.actions.onPickBackground() })
        if hasBackgroundImage {
            menu.addItem(ActionMenuItem("이미지 배경 제거") { [unowned self] in self.actions.onRemoveBackground() })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: palette.frame.minX, y: palette.frame.minY), in: self)
    }

    // MARK: Layout / drawing

    override func layout() {
        super.layout()
        let y = (bounds.height - 22) / 2
        for (i, b) in [close!, pin!, top!, palette!, trash!].enumerated() {
            b.frame = NSRect(x: 6 + CGFloat(i) * 26, y: y, width: 24, height: 22)
        }
        plus.frame = NSRect(x: bounds.width - 6 - 24, y: y, width: 24, height: 22)
        let nameX: CGFloat = 6 + 5 * 26 + 4
        let available = max(0, plus.frame.minX - 4 - nameX)
        // Leave a strip on each side that is not the text field, so the bar can be grabbed and dragged there.
        let gutter: CGFloat = available > 96 ? 24 : 0
        nameField.frame = NSRect(x: nameX + gutter, y: (bounds.height - 18) / 2,
                                 width: available - 2 * gutter, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.06).setFill()
        bounds.fill()
    }

    override var mouseDownCanMoveWindow: Bool { true }      // drag a note by its bar
    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue < 0.5 ? nil : super.hitTest(point) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}
