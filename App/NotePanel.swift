import AppKit
import StickyCore
import SwiftUI

/// Note window. Titled + transparent title bar gives system rounded corners and edge/corner resizing;
/// non-activating so clicking a note never activates the app (no Space switching, no Dock).
final class NotePanel: NSPanel {
    var textView: NoteTextView?
    var onNewNote: (() -> Void)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false          // NSPanel default would hide notes when the app is inactive
        isReleasedWhenClosed = false
        isFloatingPanel = false
        minSize = NSSize(width: 250, height: 120)   // wide enough for the icon bar plus the name box
        // collectionBehavior is deliberately left at the default: the note stays on its own Space.
    }

    /// The app has no main menu while inactive, so handle the editing shortcuts here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, mods.contains(.command), !mods.contains(.control), !mods.contains(.option),
              let key = ShortcutKey.name(forKeyCode: event.keyCode) ?? event.charactersIgnoringModifiers?.lowercased(),
              let tv = textView else {
            return super.performKeyEquivalent(with: event)
        }
        // While a secure note is locked the text view is not editable: no editing/clipboard shortcuts.
        let editingKeys: Set<String> = ["b", "i", "u", "+", "=", "-", "c", "x", "v", "a", "z"]
        if !tv.isEditable && editingKeys.contains(key) { return true }
        // Focus in the name field: clipboard/undo shortcuts belong to that field, not to the note body.
        if let editor = firstResponder as? NSText, editor !== tv {
            switch key {
            case "c": editor.copy(nil)
            case "x": editor.cut(nil)
            case "v": editor.paste(nil)
            case "a": editor.selectAll(nil)
            case "z": if mods.contains(.shift) { editor.undoManager?.redo() } else { editor.undoManager?.undo() }
            default: break
            }
            if ["c", "x", "v", "a", "z"].contains(key) { return true }
        }
        switch key {
        case "n": onNewNote?()
        case "w": onClose?()
        case "b": tv.toggleBold()
        case "i": tv.toggleItalic()
        case "u": tv.toggleUnderline()
        case "+", "=": tv.adjustSize(by: 1)
        case "-": tv.adjustSize(by: -1)
        case "c": tv.copy(nil)
        case "x": if mods.contains(.shift) { tv.toggleStrikethrough() } else { tv.cut(nil) }
        case "v": tv.paste(nil)
        case "a": tv.selectAll(nil)
        case "z": if mods.contains(.shift) { tv.undoManager?.redo() } else { tv.undoManager?.undo() }
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

/// Red outline marking a secure note. Drawn above everything and never intercepts the mouse.
final class NoteBorderView: NSView {
    var color: NSColor? { didSet { needsDisplay = true } }
    static let lineWidth: CGFloat = 3
    /// Matches the system window corner radius so the outline follows the rounded window edge.
    static let cornerRadius: CGFloat = 16

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let color else { return }
        let inset = Self.lineWidth / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                                xRadius: Self.cornerRadius - inset, yRadius: Self.cornerRadius - inset)
        path.lineWidth = Self.lineWidth
        color.setStroke()
        path.stroke()
    }
}

/// Background + text + hover toolbar + lock overlay.
final class NoteContentView: NSView {
    static let barHeight: CGFloat = 28
    let background = NoteBackgroundView()
    let scroll = NSScrollView()
    let toolbar = NoteToolbarView(frame: .zero)
    private(set) var lockHost: NSHostingView<SecureLockView>
    let border = NoteBorderView()

    init(textView: NoteTextView, lock: SecureLockView, size: NSSize) {
        lockHost = NSHostingView(rootView: lock)
        lockHost.safeAreaRegions = []   // see below: under a full-size title bar SwiftUI would pad its content
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true

        background.frame = bounds; background.autoresizingMask = [.width, .height]
        scroll.frame = bounds; scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = textView
        textView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)

        let barFrame = NSRect(x: 0, y: size.height - Self.barHeight, width: size.width, height: Self.barHeight)
        toolbar.frame = barFrame; toolbar.autoresizingMask = [.width, .minYMargin]
        lockHost.frame = bounds; lockHost.autoresizingMask = [.width, .height]
        lockHost.isHidden = true

        border.frame = bounds; border.autoresizingMask = [.width, .height]
        [background, scroll, toolbar, lockHost, border].forEach { addSubview($0) }
        setBarVisible(false, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func replaceLock(_ l: SecureLockView) { lockHost.rootView = l }

    private(set) var isBarVisible = false
    var barFrame: NSRect { NSRect(x: 0, y: bounds.height - Self.barHeight, width: bounds.width, height: Self.barHeight) }

    private func refreshCursorRects() {
        if let doc = scroll.documentView { window?.invalidateCursorRects(for: doc) }
    }

    func setBarVisible(_ visible: Bool, animated: Bool = true) {
        isBarVisible = visible
        refreshCursorRects()
        let a: CGFloat = visible ? 1 : 0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                toolbar.animator().alphaValue = a
            }
        } else { toolbar.alphaValue = a }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: notes are used while the app is inactive, so every update must work in that state.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { setBarVisible(true); updateCursor(event) }
    override func mouseExited(with event: NSEvent) { setBarVisible(false) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }

    /// I-beam over the text; the plain arrow over the hover bar, the lock screen and everything else.
    private func updateCursor(_ event: NSEvent) { applyCursor(at: convert(event.locationInWindow, from: nil)) }

    private func applyCursor(at p: NSPoint) {
        if isBarVisible && barFrame.contains(p) {
            // On the top bar: arrow, except the I-beam inside the (editable) name box.
            let q = NSPoint(x: p.x - barFrame.minX, y: p.y - barFrame.minY)
            (!toolbar.isLocked && toolbar.nameFrame.contains(q) ? NSCursor.iBeam : NSCursor.arrow).set()
            return
        }
        let overText = lockHost.isHidden && scroll.frame.contains(p)
        (overText ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    /// Sets the cursor for wherever the mouse is right now (used when this note becomes the key window).
    func refreshCursorNow() {
        guard let w = window else { return }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(p) { applyCursor(at: p) }
    }
}
