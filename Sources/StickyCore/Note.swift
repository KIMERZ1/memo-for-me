import Foundation

public struct Note: Equatable, Sendable {
    public let id: UUID
    public var created: Date
    /// Markdown body (see `MarkdownCodec`).
    public var body: String
    /// User-chosen name shown in the note's top bar. Empty = unnamed (title falls back to the first line).
    public var name: String

    public init(id: UUID = UUID(), created: Date = Date(), body: String, name: String = "") {
        self.id = id; self.created = created; self.body = body; self.name = name
    }

    /// The name if set, otherwise the first non-empty line with Markdown removed; "제목 없음" if none.
    public var title: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let plain = Note.stripMarkdown(String(line)).trimmingCharacters(in: .whitespaces)
            if !plain.isEmpty { return plain }
        }
        return FileNaming.untitled
    }

    static func stripMarkdown(_ s: String) -> String {
        var out = "", escaped = false, inTag = false
        for ch in s {
            if escaped { out.append(ch); escaped = false; continue }
            if inTag { if ch == ">" { inTag = false }; continue }
            switch ch {
            case "\\": escaped = true
            case "*": continue
            case "<": inTag = true
            default: out.append(ch)
            }
        }
        return out
    }
}
