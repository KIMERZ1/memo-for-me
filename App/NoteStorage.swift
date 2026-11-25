import AppKit
import StickyCore

struct NoteListEntry {
    let id: UUID
    let title: String
    let isSecure: Bool
}

/// Owns the notes repository for the currently chosen folder, the secure store, and folder watching.
@MainActor
final class NoteStorage {
    private let env = AppEnvironment.shared
    private(set) var repo: NoteRepository?
    private var watcher: DispatchSourceFileSystemObject?
    private var lastWarning = Date.distantPast
    var onExternalChange: (() -> Void)?
    var secure: SecureNoteStore { env.secureStore }

    init() { reopen() }

    /// (Re)opens the chosen folder. `repo` is nil when the folder is unusable.
    func reopen() {
        watcher?.cancel(); watcher = nil
        do {
            let url = try env.folderAccess.openFolder()
            repo = NoteRepository(folder: url)
            env.publishFolder(url)
            startWatching(url)
        } catch {
            repo = nil
        }
    }

    func shutdown() {
        watcher?.cancel(); watcher = nil
        env.folderAccess.closeFolder()
    }

    private func startWatching(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            // Our own atomic writes also trigger this; controllers compare content, so it is harmless.
            self?.onExternalChange?()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    /// Shows a (rate-limited) warning that the notes folder cannot be used. Content stays in the windows.
    func warnFolderUnavailable() {
        guard Date().timeIntervalSince(lastWarning) > 60 else { return }
        lastWarning = Date()
        let alert = NSAlert()
        alert.messageText = "메모 저장 폴더에 접근할 수 없어요"
        alert.informativeText = "입력한 내용은 메모창에 그대로 남아 있어요. 설정에서 저장 폴더를 다시 선택해 주세요."
        alert.addButton(withTitle: "설정 열기")
        alert.addButton(withTitle: "나중에")
        if alert.runModal() == .alertFirstButtonReturn {
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        }
    }

    func entries() -> [NoteListEntry] {
        var list: [NoteListEntry] = []
        if let repo, let notes = try? repo.loadAll() {
            list += notes.map { NoteListEntry(id: $0.id, title: $0.title, isSecure: false) }
        }
        let secureIDs = ((try? secure.allIDs()) ?? []).sorted { $0.uuidString < $1.uuidString }
        // Secure notes are listed by id only: their names are encrypted and never decrypted for the menu.
        list += secureIDs.map { NoteListEntry(id: $0, title: "", isSecure: true) }
        return list
    }
}

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}
