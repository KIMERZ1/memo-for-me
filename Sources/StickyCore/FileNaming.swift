import Foundation

public enum FileNaming {
    public static let untitled = "제목 없음"
    static let maxTitleLength = 60

    /// `<sanitized title>-<first 6 hex chars of id>.md`
    public static func fileName(title: String, id: UUID) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)
        var cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : Character($0) }
            .map(String.init).joined()
        cleaned = cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        cleaned = String(cleaned.prefix(maxTitleLength))
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { cleaned = untitled }
        let short = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(6)
        return "\(cleaned)-\(short).md"
    }
}
