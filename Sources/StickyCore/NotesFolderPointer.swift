import Foundation

/// What other programs (sticky) need to find and recognise the notes folder, without knowing anything else about the app.
/// See docs/NOTE-APP-INTEGRATION-GUIDE.md (Notes Source Contract v1, level L3).
public struct NotesFolderPointer: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    /// `notes-folder.txt`: the folder's absolute path on one line. The app is sandboxed and remembers its folder as a
    /// security-scoped bookmark, which other programs cannot read, so it writes the real path here.
    public func write(folder: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((folder.path + "\n").utf8).write(to: fileURL, options: .atomic)
    }

    /// `sticky-source.json` inside the notes folder: marks it as following the contract. Never overwritten once present.
    public static func sourceMarker(folder: URL, appVersion: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        let url = folder.appendingPathComponent("sticky-source.json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let doc: [String: Any] = ["app": "메모지", "app_version": appVersion, "contract": 1, "feed": ChangeLog.fileName]
        var data = try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
