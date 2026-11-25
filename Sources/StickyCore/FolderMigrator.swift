import Foundation

public enum FolderMigrator {
    /// Moves `*.md` notes and `changes.jsonl`. Refuses (moves nothing) if any target name exists.
    public static func move(from: URL, to: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil).filter {
            $0.pathExtension == "md" || $0.lastPathComponent == ChangeLog.fileName
        }
        for item in items where fm.fileExists(atPath: to.appendingPathComponent(item.lastPathComponent).path) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: item.lastPathComponent])
        }
        var moved: [(URL, URL)] = []
        do {
            for item in items {
                let target = to.appendingPathComponent(item.lastPathComponent)
                try fm.moveItem(at: item, to: target)
                moved.append((item, target))
            }
        } catch {
            for (orig, target) in moved.reversed() { try? fm.moveItem(at: target, to: orig) }
            throw error
        }
    }
}
