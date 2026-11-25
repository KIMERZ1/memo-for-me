import AppKit
import StickyCore

@MainActor
final class NoteWindowManager {
    let storage = NoteStorage()
    private let env = AppEnvironment.shared
    private var controllers: [UUID: NoteWindowController] = [:]
    private var externalTimer: Timer?
    static let defaultSize = NSSize(width: 280, height: 300)

    init() {
        storage.onExternalChange = { [weak self] in self?.scheduleExternalCheck() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockSecureNotesOffSpace() }
        }
        NotificationCenter.default.addObserver(forName: .notesFolderChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
    }

    // MARK: Launch / restore

    /// Reopens every note that was open when the app last quit.
    func restoreAll() {
        var folderProblem = false
        let states = env.stateStore.all()
        for s in states where controllers[s.noteID] == nil {
            if !s.isOpen {
                // Closed notes stay in the list; forget the window record of ones whose file is gone.
                let gone = s.isSecure ? ((try? env.secureStore.allIDs())?.contains(s.noteID) != true)
                                      : (storage.repo != nil && storage.repo?.fileURL(for: s.noteID) == nil)
                if gone { env.stateStore.remove(noteID: s.noteID) }
                continue
            }
            // Every note that was open comes back — including empty ones that were never typed in
            // (those have no file yet and simply start blank).
            if s.isSecure {
                let stored = (try? env.secureStore.allIDs())?.contains(s.noteID) == true
                _ = makeController(s, created: Date(), load: .none, startsUnlocked: !stored)
            } else if let repo = storage.repo {
                if let note = try? repo.load(id: s.noteID) { _ = makeController(s, created: note.created, load: .repository) }
                else { _ = makeController(s, created: Date(), load: .none) }
            } else {
                folderProblem = true    // keep state; windows come back once the folder works again
            }
        }
        // Notes on disk that have no window record at all (state file lost, or written by another tool):
        // nothing says they were closed on purpose, so show them too.
        if let repo = storage.repo, let notes = try? repo.loadAll() {
            let known = Set(states.map(\.noteID))
            for n in notes where !known.contains(n.id) && controllers[n.id] == nil {
                let state = NoteWindowState(noteID: n.id, isSecure: false, frame: cascadeFrame(), colorName: .yellow,
                                            backgroundImageFile: nil, isPinnedHere: false, floatsOnTop: false)
                _ = makeController(state, created: n.created, load: .repository)
            }
        }
        NSLog("restoreAll: states=%d open=%d folderOK=%d", states.count, controllers.count, storage.repo != nil ? 1 : 0)
        if folderProblem { DispatchQueue.main.async { self.storage.warnFolderUnavailable() } }
    }

    private func cascadeFrame() -> CGRect {
        let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let n = controllers.count % 6
        let size = Self.defaultSize
        return CGRect(x: v.minX + 40 + CGFloat(n) * 28, y: v.maxY - size.height - 40 - CGFloat(n) * 28,
                      width: size.width, height: size.height)
    }

    private enum LoadKind { case none, repository, secure }

    private func makeController(_ state: NoteWindowState, created: Date, load: LoadKind, startsUnlocked: Bool = false) -> NoteWindowController? {
        var s = state
        s.frame = Self.onScreen(s.frame)
        let c = NoteWindowController(state: s, created: created, manager: self, storage: storage, startsUnlocked: startsUnlocked)
        if load == .repository { c.editor.loadFromRepository() }
        controllers[s.noteID] = c
        c.setOpen(true)
        c.show(focus: false)
        return c
    }

    private static func onScreen(_ f: CGRect) -> CGRect {
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(f) }) { return f }
        let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return CGRect(x: v.minX + 40, y: v.maxY - f.height - 40, width: f.width, height: f.height)
    }

    // MARK: Create / open

    func newNote(secure: Bool = false) {
        let state = NoteWindowState(noteID: UUID(), isSecure: secure, frame: cascadeFrame(), colorName: .yellow,
                                    backgroundImageFile: nil, isPinnedHere: false, floatsOnTop: false)
        guard let c = makeController(state, created: Date(), load: .none, startsUnlocked: true) else { return }
        c.show()
    }

    /// Opens a note from the list (or brings an already-open one to the front).
    func open(id: UUID) {
        if let c = controllers[id] {
            NSApp.activate()
            c.show()
            return
        }
        let isSecure = (try? env.secureStore.allIDs())?.contains(id) == true
        var state = env.stateStore.all().first { $0.noteID == id }
            ?? NoteWindowState(noteID: id, isSecure: isSecure,
                               frame: CGRect(x: 80, y: 200, width: Self.defaultSize.width, height: Self.defaultSize.height),
                               colorName: .yellow, backgroundImageFile: nil, isPinnedHere: false, floatsOnTop: false)
        state.isSecure = isSecure
        var created = Date()
        if !isSecure {
            guard let note = try? storage.repo?.load(id: id) else { return }
            created = note.created
        }
        state.frame = Self.onScreen(state.frame)
        if let c = makeController(state, created: created, load: isSecure ? .none : .repository) {
            NSApp.activate()
            c.show()
        }
    }

    // MARK: Close / delete

    /// ⌘W: hide the window; the note stays on disk and in the list.
    func close(_ c: NoteWindowController) {
        let stored = c.editor.isSecure
            ? ((try? env.secureStore.allIDs())?.contains(c.id) ?? false)
            : (storage.repo?.fileURL(for: c.id) != nil)
        if !c.editor.hasContent && !stored {
            remove(c); return          // empty, never saved: nothing worth keeping
        }
        c.tearDown()
        c.setOpen(false)
        controllers[c.id] = nil
    }

    func requestDelete(_ c: NoteWindowController) {
        if c.editor.isSecure || c.editor.hasContent {
            let alert = NSAlert()
            alert.messageText = "이 메모지를 삭제할까요?"
            alert.informativeText = "삭제하면 되돌릴 수 없어요."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "삭제").hasDestructiveAction = true
            alert.addButton(withTitle: "취소")
            alert.beginSheetModal(for: c.panel) { [weak self] resp in
                if resp == .alertFirstButtonReturn { self?.remove(c) }
            }
        } else { remove(c) }
    }

    private func remove(_ c: NoteWindowController) {
        c.editor.deleteStoredNote()
        if let f = c.state.backgroundImageFile { env.backgroundStore.remove(f) }
        env.stateStore.remove(noteID: c.id)
        c.tearDown()
        controllers[c.id] = nil
    }

    // MARK: Lifecycle

    func flushAll() {
        controllers.values.forEach { $0.editor.flush(); $0.persist() }
        env.stateStore.flush()
    }

    private func lockSecureNotesOffSpace() {
        for c in controllers.values where c.editor.isSecure && !c.panel.isOnActiveSpace { c.lock() }
    }

    private func folderChanged() {
        flushAll()
        for c in controllers.values where !c.editor.isSecure { c.tearDown() }
        controllers = controllers.filter { $0.value.editor.isSecure }
        storage.reopen()
        restoreAll()
    }

    private func scheduleExternalCheck() {
        externalTimer?.invalidate()
        externalTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyExternalChanges() }
        }
    }

    private func applyExternalChanges() {
        for c in Array(controllers.values) where c.editor.checkExternalChange() == .deleted {
            env.stateStore.remove(noteID: c.id)
            c.tearDown()
            controllers[c.id] = nil
        }
    }

    // MARK: List

    /// Saved notes plus every open window — a new note that has not been typed in yet has no file,
    /// but it must still be listed.
    func listItems() -> [(entry: NoteListEntry, isOpen: Bool)] {
        var items = storage.entries().map { (entry: $0, isOpen: controllers[$0.id] != nil) }
        let listed = Set(items.map { $0.entry.id })
        for c in controllers.values where !listed.contains(c.id) {
            let firstLine = c.editor.textView.string
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
            let name = c.editor.name.trimmingCharacters(in: .whitespaces)
            items.append((NoteListEntry(id: c.id, title: c.editor.isSecure ? "" : (name.isEmpty ? (firstLine ?? "새 메모지") : name), isSecure: c.editor.isSecure), true))
        }
        return items
    }
}
