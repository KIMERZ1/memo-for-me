import Foundation

public enum ChangeEvent: String, Sendable { case created, updated, deleted }

/// Append-only `changes.jsonl` that other programs (sticky) read. Never contains note bodies.
/// Each line carries `v`, the contract version (docs/NOTE-APP-INTEGRATION-GUIDE.md).
public struct ChangeLog: Sendable {
    public static let fileName = "changes.jsonl"
    let folder: URL
    let now: @Sendable () -> Date

    public init(folder: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.folder = folder; self.now = now
    }

    public func append(event: ChangeEvent, note: Note, file: String) throws {
        let record: [String: Any] = [
            "v": 1,
            "ts": ISO8601DateFormatter().string(from: now()),
            "event": event.rawValue,
            "id": note.id.uuidString,
            "file": file,
            "title": note.title,
        ]
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        let path = folder.appendingPathComponent(Self.fileName).path
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        guard written == data.count else { throw CocoaError(.fileWriteUnknown) }
    }
}
