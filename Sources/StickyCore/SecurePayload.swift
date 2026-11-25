import Foundation

/// What a secure note stores inside its encrypted file: the name and the body.
/// Older files hold the plain body only; `decode` accepts both.
public struct SecurePayload: Equatable, Sendable {
    public var name: String
    public var body: String

    public init(name: String, body: String) { self.name = name; self.body = body }

    private struct Envelope: Codable { var v: Int; var name: String; var body: String }

    public func encoded() -> String {
        let data = try? JSONEncoder().encode(Envelope(v: 1, name: name, body: body))
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? body
    }

    public static func decode(_ stored: String) -> SecurePayload {
        if let e = try? JSONDecoder().decode(Envelope.self, from: Data(stored.utf8)), e.v == 1 {
            return SecurePayload(name: e.name, body: e.body)
        }
        return SecurePayload(name: "", body: stored)
    }
}
