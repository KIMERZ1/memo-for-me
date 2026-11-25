import Foundation

public enum NoteRepositoryError: Error { case notFound, malformed }

/// One note = one `.md` file (front matter: id, created, type) in `folder`.
public final class NoteRepository {
    public let folder: URL
    private let log: ChangeLog
    private let fm = FileManager.default
    private var index: [UUID: String] = [:]
    private let iso = ISO8601DateFormatter()

    public init(folder: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.folder = folder
        self.log = ChangeLog(folder: folder, now: now)
    }

    // MARK: Public API

    @discardableResult
    public func save(_ note: Note) throws -> URL {
        let name = FileNaming.fileName(title: note.title, id: note.id)
        let url = folder.appendingPathComponent(name)
        let content = serialize(note)
        let old = locate(note.id)

        if let old, old.lastPathComponent == name,
           (try? String(contentsOf: old, encoding: .utf8)) == content {
            return old   // nothing changed: no write, no event
        }
        try Data(content.utf8).write(to: url, options: .atomic)
        if let old, old.lastPathComponent != name { try? fm.removeItem(at: old) }
        index[note.id] = name
        try log.append(event: old == nil ? .created : .updated, note: note, file: name)
        return url
    }

    public func load(id: UUID) throws -> Note {
        guard let url = locate(id) else { throw NoteRepositoryError.notFound }
        return try parse(url)
    }

    public func loadAll() throws -> [Note] {
        try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .compactMap { try? parse($0) }
            .sorted { $0.created < $1.created }
    }

    public func delete(id: UUID) throws {
        guard let url = locate(id) else { throw NoteRepositoryError.notFound }
        let note = try? parse(url)
        try fm.removeItem(at: url)
        index[id] = nil
        if let note { try log.append(event: .deleted, note: note, file: url.lastPathComponent) }
    }

    public func fileURL(for id: UUID) -> URL? { locate(id) }

    // MARK: Internals

    private func locate(_ id: UUID) -> URL? {
        if let name = index[id] {
            let u = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) { return u }
            index[id] = nil
        }
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for u in files where u.pathExtension == "md" {
            if let n = try? parse(u), n.id == id { index[id] = u.lastPathComponent; return u }
        }
        return nil
    }

    private func serialize(_ n: Note) -> String {
        var head = "---\nid: \(n.id.uuidString)\ncreated: \(iso.string(from: n.created))\ntype: note\n"
        let name = n.name.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { head += "name: \(name)\n" }
        return head + "---\n\(n.body)"
    }

    private func parse(_ url: URL) throws -> Note {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.hasPrefix("---\n") else { throw NoteRepositoryError.malformed }
        let rest = text.dropFirst(4)
        guard let end = rest.range(of: "\n---\n") ?? (rest.hasSuffix("\n---") ? rest.range(of: "\n---", options: .backwards) : nil)
        else { throw NoteRepositoryError.malformed }
        var id: UUID?, created: Date?, name = ""
        for line in rest[..<end.lowerBound].split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "id" { id = UUID(uuidString: parts[1]) }
            if parts[0] == "created" { created = iso.date(from: parts[1]) }
            if parts[0] == "name" { name = parts[1] }
        }
        guard let id, let created else { throw NoteRepositoryError.malformed }
        return Note(id: id, created: created, body: String(rest[end.upperBound...]), name: name)
    }
}
