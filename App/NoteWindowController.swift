import AppKit
import SwiftUI
import StickyCore

@MainActor
final class NoteWindowController: NSObject, NSWindowDelegate {
    private(set) var state: NoteWindowState
    let panel: NotePanel
    let editor: NoteEditorController
    private let content: NoteContentView
    private let formatWindow: FormatBarWindow
    private unowned let manager: NoteWindowManager
    private let env = AppEnvironment.shared
    private let auth: Authenticator = LAAuthenticator()
    private var persistTimer: Timer?
    private var idleTimer: Timer?
    private(set) var isLocked: Bool
    static let idleLockInterval: TimeInterval = 15 * 60

    var id: UUID { state.noteID }

    init(state: NoteWindowState, created: Date, manager: NoteWindowManager, storage: NoteStorage, startsUnlocked: Bool = false) {
        self.state = state
        self.manager = manager
        self.isLocked = state.isSecure && !startsUnlocked

        let tv = NoteTextView(frame: .zero)
        tv.setUp()
        editor = NoteEditorController(id: state.noteID, created: created, isSecure: state.isSecure, textView: tv, storage: storage)
        panel = NotePanel(frame: state.frame)
        panel.textView = tv

        var unlock: () -> Void = {}
        formatWindow = FormatBarWindow()
        content = NoteContentView(textView: tv,
                                  lock: SecureLockView(onUnlock: { unlock() }), size: state.frame.size)
        super.init()

        // Real actions (need `self`).
        content.toolbar.actions = ToolbarActions(
            onTogglePin: { [weak self] in self?.togglePin() },
            onToggleFloat: { [weak self] in self?.toggleFloat() },
            onChangeColor: { [weak self] c in self?.changeColor(c) },
            onPickBackground: { [weak self] in self?.pickBackground() },
            onRemoveBackground: { [weak self] in self?.removeBackground() },
            onClose: { [weak self] in guard let self else { return }; self.manager.close(self) },
            onDelete: { [weak self] in guard let self else { return }; self.manager.requestDelete(self) },
            onNewNote: { [weak self] in guard let self else { return }; self.manager.newNote(secure: self.state.isSecure) },
            onNameChanged: { [weak self] n in self?.editor.setName(n) },
            onNameCommit: { [weak self] in guard let self else { return }; self.panel.makeFirstResponder(self.editor.textView) })
        editor.onNameLoaded = { [weak self] n in self?.content.toolbar.setName(n) }
        unlock = { [weak self] in self?.unlock() }
        formatWindow.view.actions = FormatBarActions(
            onBold: { [weak self] in self?.format { $0.toggleBold() } },
            onItalic: { [weak self] in self?.format { $0.toggleItalic() } },
            onUnderline: { [weak self] in self?.format { $0.toggleUnderline() } },
            onStrike: { [weak self] in self?.format { $0.toggleStrikethrough() } })
        editor.onSelectionChanged = { [weak self] in self?.updateFormatBar() }
        tv.onMouseDownFinished = { [weak self] in self?.updateFormatBar() }
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: content.scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFormatBar() }
        }
        content.scroll.contentView.postsBoundsChangedNotifications = true
        tv.excludedCursorRects = { [weak self] in
            guard let self, self.content.isBarVisible else { return [] }
            return [self.editor.textView.convert(self.content.barFrame, from: self.content)]
        }
        content.replaceLock(SecureLockView(onUnlock: { [weak self] in self?.unlock() }))

        panel.contentView = content
        panel.delegate = self
        panel.onNewNote = { [weak self] in guard let self else { return }; self.manager.newNote(secure: self.state.isSecure) }
        panel.onClose = { [weak self] in guard let self else { return }; self.manager.close(self) }
        editor.onEdited = { [weak self] in self?.resetIdleTimer() }
        applyState()
    }

    // MARK: State

    private func applyState() {
        content.background.color = NoteAppearance.color(for: state.colorName)
        if let f = state.backgroundImageFile {
            content.background.image = NSImage(contentsOf: env.backgroundStore.url(for: f))
        } else { content.background.image = nil }
        panel.level = state.floatsOnTop ? .floating : .normal
        panel.isMovable = !state.isPinnedHere
        content.toolbar.isPinned = state.isPinnedHere
        content.toolbar.floatsOnTop = state.floatsOnTop
        content.toolbar.hasBackgroundImage = state.backgroundImageFile != nil
        content.toolbar.isLocked = state.isSecure && isLocked
        content.border.color = state.isSecure ? .systemRed : nil
        content.lockHost.isHidden = !(state.isSecure && isLocked)
        editor.textView.isEditable = !(state.isSecure && isLocked)
    }

    func persist() {
        state.frame = panel.frame
        env.stateStore.update(state)
    }

    func setOpen(_ open: Bool) { state.isOpen = open; persist() }

    private func schedulePersist() {
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.persist() }
        }
    }
    func windowDidMove(_ notification: Notification) { schedulePersist() }
    func windowDidResize(_ notification: Notification) { schedulePersist() }

    // MARK: Show / hide

    func show(focus: Bool = true) {
        if state.isSecure && isLocked { applyState() }
        panel.makeKeyAndOrderFront(nil)
        if focus && !(state.isSecure && isLocked) { panel.makeFirstResponder(editor.textView) }
        // Only a note the user opens/creates on purpose asks for Touch ID; at launch they stay locked
        // (with their "Touch ID로 열기" button) instead of popping up one prompt per secure note.
        if focus && state.isSecure && isLocked { unlock() }
    }

    /// Flushes and removes the window (state/storage untouched).
    func tearDown() {
        persistTimer?.invalidate(); idleTimer?.invalidate()
        formatWindow.hide()
        editor.flush()
        if state.isSecure { editor.clearText(); editor.clearName(); editor.textView.undoManager?.removeAllActions() }
        panel.delegate = nil
        panel.orderOut(nil)
    }

    // MARK: Format bar (appears under highlighted text)

    private func format(_ apply: (NoteTextView) -> Void) {
        apply(editor.textView)
        panel.makeFirstResponder(editor.textView)
        updateFormatBar()
    }

    func updateFormatBar() {
        let tv = editor.textView
        // While the mouse button is down (drag-selecting) leave the bar alone: showing/hiding a window mid-drag
        // makes macOS reset the cursor to an arrow. It appears once the button is released.
        if NSEvent.pressedMouseButtons & 1 != 0 { formatWindow.hide(); return }
        let locked = state.isSecure && isLocked
        guard !locked, panel.isKeyWindow, tv.selectedRange().length > 0, let lm = tv.layoutManager,
              let tc = tv.textContainer else { formatWindow.hide(); return }
        let glyphs = lm.glyphRange(forCharacterRange: tv.selectedRange(), actualCharacterRange: nil)
        var r = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        r.origin.x += tv.textContainerOrigin.x
        r.origin.y += tv.textContainerOrigin.y
        let st = tv.selectionStyle()
        formatWindow.view.update(FormatBarStyle(bold: st.bold, italic: st.italic, underline: st.underline, strike: st.strike))
        let onScreen = panel.convertToScreen(tv.convert(r, to: nil))
        formatWindow.show(below: onScreen, over: panel)
        content.refreshCursorNow()
    }

    func windowDidResignKey(_ notification: Notification) { formatWindow.hide() }
    func windowDidBecomeKey(_ notification: Notification) {
        updateFormatBar()
        // Clicking another note makes it key: show the right cursor right now, not after the next mouse move.
        panel.invalidateCursorRects(for: editor.textView)
        content.refreshCursorNow()
    }

    // MARK: Toolbar actions

    private func togglePin() { state.isPinnedHere.toggle(); applyState(); persist() }
    private func toggleFloat() { state.floatsOnTop.toggle(); applyState(); persist() }

    private func changeColor(_ c: NoteColor) {
        state.colorName = c
        removeBackground(persistNow: false)
        applyState(); persist()
    }

    private func removeBackground(persistNow: Bool = true) {
        if let f = state.backgroundImageFile { env.backgroundStore.remove(f) }
        state.backgroundImageFile = nil
        applyState()
        if persistNow { persist() }
    }

    private func pickBackground() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.image]
        open.allowsMultipleSelection = false
        open.prompt = "선택"
        open.beginSheetModal(for: panel) { [weak self] resp in
            guard resp == .OK, let url = open.url, let self else { return }
            do {
                let name = try self.env.backgroundStore.importImage(from: url)
                if let old = self.state.backgroundImageFile { self.env.backgroundStore.remove(old) }
                self.state.backgroundImageFile = name
                self.applyState(); self.persist()
            } catch {
                NSAlert(error: error).beginSheetModal(for: self.panel)
            }
        }
    }

    // MARK: Secure notes

    func unlock() {
        guard state.isSecure, isLocked else { return }
        Task { @MainActor in _ = await authenticateAndLoad() }
    }

    private func authenticateAndLoad() async -> Bool {
        guard await auth.authenticate(reason: "보안 메모지를 엽니다") else { return false }
        do { try editor.loadSecure() } catch {
            if (try? env.secureStore.allIDs())?.contains(id) == true { return false }
        }
        isLocked = false
        applyState(); resetIdleTimer()
        panel.makeFirstResponder(editor.textView)
        return true
    }

    func lock() {
        guard state.isSecure, !isLocked else { return }
        editor.flush(); editor.clearText(); editor.clearName()
        editor.textView.undoManager?.removeAllActions()   // undo history would still hold the plaintext
        isLocked = true
        idleTimer?.invalidate()
        applyState()
    }

    private func resetIdleTimer() {
        guard state.isSecure else { return }
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleLockInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        }
    }
}
