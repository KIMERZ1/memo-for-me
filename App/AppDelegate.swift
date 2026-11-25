import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var manager: NoteWindowManager!
    private let settings = SettingsWindowController()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager = NoteWindowManager()
        statusItem = StatusItemController(
            onNewNote: { [weak self] in self?.manager.newNote() },
            onNewSecureNote: { [weak self] in self?.manager.newNote(secure: true) },
            onOpenSettings: { [weak self] in self?.settings.show() },
            listProvider: { [weak self] in self?.manager.listItems() ?? [] },
            onOpenNote: { [weak self] id in self?.manager.open(id: id) })
        NotificationCenter.default.addObserver(forName: .openSettingsRequested, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settings.show() }
        }
        manager.restoreAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.flushAll()
        manager.storage.shutdown()
    }
}
