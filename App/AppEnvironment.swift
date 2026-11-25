import Foundation
import StickyCore

/// Shared app-wide services.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let supportDirectory: URL
    let folderAccess: FolderAccess
    let stateStore: WindowStateStore
    let secureStore: SecureNoteStore
    let backgroundStore: BackgroundImageStore
    let folderPointer: NotesFolderPointer

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyNotes", isDirectory: true)
        supportDirectory = base
        folderAccess = FolderAccess(defaults: .standard, defaultFolder: base.appendingPathComponent("Notes"))
        stateStore = WindowStateStore(fileURL: base.appendingPathComponent("state.json"))
        secureStore = SecureNoteStore(directory: base.appendingPathComponent("Secure"), keys: KeychainKeyProvider())
        backgroundStore = BackgroundImageStore(directory: base.appendingPathComponent("Backgrounds"))
        folderPointer = NotesFolderPointer(fileURL: base.appendingPathComponent("notes-folder.txt"))
    }

    /// Tell other programs (sticky) where the notes are and that the folder follows the contract. Failures are harmless.
    func publishFolder(_ folder: URL) {
        try? folderPointer.write(folder: folder)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        try? NotesFolderPointer.sourceMarker(folder: folder, appVersion: version)
    }
}
