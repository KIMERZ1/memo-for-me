import Foundation
import CryptoKit

/// Encrypted notes (AES-256-GCM) kept in an app-private directory.
/// Deliberately knows nothing about `ChangeLog` or `NoteRepository`.
public final class SecureNoteStore {
    private let directory: URL
    private let keys: KeyProvider
    private let fm = FileManager.default

    public init(directory: URL, keys: KeyProvider) {
        self.directory = directory
        self.keys = keys
    }

    public func save(id: UUID, body: String) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let sealed = try AES.GCM.seal(Data(body.utf8), using: keys.key())
        guard let combined = sealed.combined else { throw CocoaError(.coderInvalidValue) }
        try combined.write(to: url(id), options: .atomic)
    }

    public func load(id: UUID) throws -> String {
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url(id)))
        let plain = try AES.GCM.open(box, using: keys.key())
        guard let s = String(data: plain, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return s
    }

    public func delete(id: UUID) throws { try fm.removeItem(at: url(id)) }

    public func allIDs() throws -> [UUID] {
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try fm.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".enc") }
            .compactMap { UUID(uuidString: String($0.dropLast(4))) }
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).enc") }
}
