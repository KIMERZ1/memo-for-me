import AppKit
import StickyCore

/// Connects one note to its text view: loading, debounced saving, external-change handling.
@MainActor
final class NoteEditorController: NSObject, NSTextViewDelegate {
    let id: UUID
    let created: Date
    private(set) var isSecure: Bool
    let textView: NoteTextView
    private let storage: NoteStorage
    private var lastKnownBody: String?   // body as last read from / written to disk
    private var lastKnownName = ""
    private(set) var name = ""
    private var dirty = false
    private var replacing = false
    private var timer: Timer?
    static let debounce: TimeInterval = 0.7

    var onEdited: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    /// Called when the name is loaded from disk (not when the user types it).
    var onNameLoaded: ((String) -> Void)?

    init(id: UUID, created: Date, isSecure: Bool, textView: NoteTextView, storage: NoteStorage) {
        self.id = id; self.created = created; self.isSecure = isSecure
        self.textView = textView; self.storage = storage
        super.init()
        textView.delegate = self
    }

    var hasContent: Bool {
        !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var isEditingInProgress: Bool { textView.hasMarkedText() }

    // MARK: Load

    /// Loads a normal note from the repository. Returns false if it does not exist there.
    @discardableResult
    func loadFromRepository() -> Bool {
        guard let repo = storage.repo, let note = try? repo.load(id: id) else { return false }
        setBody(note.body)
        lastKnownBody = note.body
        lastKnownName = note.name
        applyLoadedName(note.name)
        return true
    }

    func loadSecure() throws {
        let payload = SecurePayload.decode(try storage.secure.load(id: id))
        setBody(payload.body)
        applyLoadedName(payload.name)
    }

    private func applyLoadedName(_ n: String) {
        name = n
        onNameLoaded?(n)
    }

    /// The user edited the name in the top bar.
    func setName(_ new: String) {
        guard new != name else { return }
        name = new
        dirty = true
        onEdited?()
        scheduleSave()
    }

    /// Forget the name without saving (used when a secure note locks).
    func clearName() { name = ""; onNameLoaded?("") }

    func setBody(_ md: String) {
        replacing = true
        let sel = textView.selectedRange()
        textView.textStorage?.setAttributedString(MarkdownCodec.decode(md, baseSize: NoteAppearance.baseFontSize))
        let len = textView.string.utf16.count
        textView.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        replacing = false
        dirty = false
    }

    func clearText() {
        replacing = true
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        replacing = false
        dirty = false
    }

    // MARK: Save

    func textViewDidChangeSelection(_ notification: Notification) { onSelectionChanged?() }

    func textDidChange(_ notification: Notification) {
        guard !replacing else { return }
        dirty = true
        onEdited?()
        scheduleSave()
    }

    private func scheduleSave() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.debounce, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
    }

    private func timerFired() {
        // Never save/reload while a Korean (or other IME) composition is in progress.
        if textView.hasMarkedText() {
            timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.timerFired() }
            }
            return
        }
        flush()
    }

    var currentMarkdown: String {
        MarkdownCodec.encode(textView.attributedString(), baseSize: NoteAppearance.baseFontSize)
    }

    /// Writes pending edits immediately (also called on quit/close).
    func flush() {
        timer?.invalidate(); timer = nil
        guard dirty else { return }
        let body = currentMarkdown
        if isSecure {
            try? storage.secure.save(id: id, body: SecurePayload(name: name, body: body).encoded())
            dirty = false
            return
        }
        guard let repo = storage.repo else { storage.warnFolderUnavailable(); return }
        let exists = repo.fileURL(for: id) != nil
        if !exists && !hasContent { dirty = false; return }

        // Someone else (e.g. Claude or the user's editor) changed the file since we last saw it?
        if let known = lastKnownBody, let disk = try? repo.load(id: id), disk.body != known, disk.body != body {
            // Keep our text as a separate note copy; show the external version here.
            try? repo.save(Note(id: UUID(), created: Date(), body: body, name: name))
            setBody(disk.body)
            lastKnownBody = disk.body
            lastKnownName = disk.name
            applyLoadedName(disk.name)
            return
        }
        do {
            try repo.save(Note(id: id, created: created, body: body, name: name))
            lastKnownBody = body
            lastKnownName = name
            dirty = false
        } catch {
            storage.warnFolderUnavailable()
        }
    }

    // MARK: External changes

    enum ExternalResult { case unchanged, updated, deleted }

    /// Called when the notes folder changed. Applies the on-disk version unless the user is mid-edit.
    func checkExternalChange() -> ExternalResult {
        guard !isSecure, !dirty, !isEditingInProgress, let repo = storage.repo,
              let known = lastKnownBody else { return .unchanged }
        guard let disk = try? repo.load(id: id) else {
            return repo.fileURL(for: id) == nil ? .deleted : .unchanged
        }
        if disk.body != known || disk.name != lastKnownName {
            setBody(disk.body)
            lastKnownBody = disk.body
            lastKnownName = disk.name
            applyLoadedName(disk.name)
            return .updated
        }
        return .unchanged
    }

    // MARK: Deletion

    func deleteStoredNote() {
        timer?.invalidate(); timer = nil; dirty = false
        if isSecure { try? storage.secure.delete(id: id) } else { try? storage.repo?.delete(id: id) }
    }
}
