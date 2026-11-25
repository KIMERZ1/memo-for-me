import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onNewNote: () -> Void
    private let onNewSecureNote: () -> Void
    private let onOpenSettings: () -> Void
    private let listProvider: () -> [(entry: NoteListEntry, isOpen: Bool)]
    private let onOpenNote: (UUID) -> Void
    private let listMenu = NSMenu()

    init(onNewNote: @escaping () -> Void, onNewSecureNote: @escaping () -> Void, onOpenSettings: @escaping () -> Void,
         listProvider: @escaping () -> [(entry: NoteListEntry, isOpen: Bool)], onOpenNote: @escaping (UUID) -> Void) {
        self.onNewNote = onNewNote; self.onNewSecureNote = onNewSecureNote; self.onOpenSettings = onOpenSettings
        self.listProvider = listProvider; self.onOpenNote = onOpenNote
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "메모지")
        let menu = NSMenu()
        menu.addItem(item("메모지 추가", #selector(newNote)))
        menu.addItem(item("보안 메모지 추가", #selector(newSecureNote)))
        let listItem = NSMenuItem(title: "메모지 목록", action: nil, keyEquivalent: "")
        listMenu.delegate = self
        listItem.submenu = listMenu
        menu.addItem(listItem)
        menu.addItem(item("설정…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("종료", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    /// Rebuilt every time the submenu opens so it always reflects what is on disk.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === listMenu else { return }
        menu.removeAllItems()
        let items = listProvider()
        if items.isEmpty {
            let empty = NSMenuItem(title: "메모지가 없어요", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        var secureCount = 0
        for (entry, isOpen) in items {
            var title: String
            if entry.isSecure {
                secureCount += 1
                title = "🔒 보안 메모지 \(secureCount)"   // never show the name: it is encrypted and stays behind Touch ID
            }
            else { title = String(entry.title.prefix(30)) }
            let mi = NSMenuItem(title: title, action: #selector(openNote(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = entry.id
            mi.state = isOpen ? .on : .off
            menu.addItem(mi)
        }
    }

    @objc private func openNote(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { onOpenNote(id) }
    }
    @objc private func newNote() { onNewNote() }
    @objc private func newSecureNote() { onNewSecureNote() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
