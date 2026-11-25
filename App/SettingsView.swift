import SwiftUI
import AppKit
import StickyCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var path: String = ""
    @Published var status: FolderStatus = .usingDefault
    private let access: FolderAccess

    init(access: FolderAccess) { self.access = access; refresh() }

    func refresh() {
        path = access.currentFolder.path
        status = access.status
    }

    func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func revealInFinder() { NSWorkspace.shared.activateFileViewerSelecting([access.currentFolder]) }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        panel.message = "메모(.md)를 저장할 폴더를 선택하세요."
        guard panel.runModal() == .OK, let newFolder = panel.url else { return }
        let oldFolder = access.currentFolder
        let hadNotes = status == .ok || status == .usingDefault
        var shouldMove = false

        if hadNotes, oldFolder.standardizedFileURL != newFolder.standardizedFileURL,
           (try? FileManager.default.contentsOfDirectory(atPath: oldFolder.path).contains { $0.hasSuffix(".md") }) == true {
            let alert = NSAlert()
            alert.messageText = "기존 메모를 새 폴더로 이동할까요?"
            alert.informativeText = "이동하지 않으면 새 폴더는 빈 상태로 시작하고, 기존 메모는 이전 폴더에 남습니다."
            alert.addButton(withTitle: "이동")
            alert.addButton(withTitle: "이동 안 함")
            alert.addButton(withTitle: "취소")
            switch alert.runModal() {
            case .alertFirstButtonReturn: shouldMove = true
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        do {
            if shouldMove {
                let started = newFolder.startAccessingSecurityScopedResource()
                defer { if started { newFolder.stopAccessingSecurityScopedResource() } }
                try access.withAccess { old in try FolderMigrator.move(from: old, to: newFolder) }
            }
            try access.setFolder(newFolder)
            NotificationCenter.default.post(name: .notesFolderChanged, object: nil)
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }
}

extension Notification.Name {
    static let notesFolderChanged = Notification.Name("notesFolderChanged")
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("저장 위치") {
                Text(model.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2).truncationMode(.middle)
                HStack {
                    Button("폴더 선택…") { model.chooseFolder() }
                    Button("Finder에서 보기") { model.revealInFinder() }
                    Button("경로 복사") { model.copyPath() }
                }
                switch model.status {
                case .usingDefault:
                    Label("아직 폴더를 고르지 않아 앱 기본 폴더를 쓰고 있어요. Claude가 읽을 폴더를 선택하세요.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                case .missing:
                    Label("선택한 폴더를 찾을 수 없어요. 폴더를 다시 선택하세요. (메모창의 내용은 유지됩니다)", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                case .permissionLost:
                    Label("폴더 접근 권한이 사라졌어요. 폴더를 다시 선택하세요. (메모창의 내용은 유지됩니다)", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                case .ok: EmptyView()
                }
            }
            Section("보안 메모지") {
                Text("보안 메모지는 암호화되어 앱 내부에만 저장되며 이 폴더와 Notion 연동 대상에 포함되지 않습니다. 기기를 초기화하거나 바꾸면 복구할 수 없습니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
