import XCTest
import CryptoKit
@testable import StickyCore

struct FixedKey: KeyProvider {
    let k: SymmetricKey
    func key() throws -> SymmetricKey { k }
}

final class SecureNoteStoreTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func store(_ key: SymmetricKey = SymmetricKey(size: .bits256)) -> SecureNoteStore {
        SecureNoteStore(directory: dir, keys: FixedKey(k: key))
    }

    func testRoundTrip() throws {
        let s = store(); let id = UUID()
        try s.save(id: id, body: "OPENAI_KEY=sk-secret-123")
        XCTAssertEqual(try s.load(id: id), "OPENAI_KEY=sk-secret-123")
        XCTAssertEqual(try s.allIDs(), [id])
    }

    func testCiphertextDoesNotContainPlaintext() throws {
        let s = store(); let id = UUID()
        try s.save(id: id, body: "sk-secret-123")
        let bytes = try Data(contentsOf: dir.appendingPathComponent("\(id.uuidString).enc"))
        XCTAssertNil(bytes.range(of: Data("sk-secret-123".utf8)))
    }

    func testWrongKeyFails() throws {
        let id = UUID()
        try store().save(id: id, body: "x")
        XCTAssertThrowsError(try store().load(id: id))
    }

    func testSameBodyTwiceProducesDifferentCiphertext() throws {
        let s = store(); let id = UUID()
        try s.save(id: id, body: "same")
        let a = try Data(contentsOf: dir.appendingPathComponent("\(id.uuidString).enc"))
        try s.save(id: id, body: "same")
        let b = try Data(contentsOf: dir.appendingPathComponent("\(id.uuidString).enc"))
        XCTAssertNotEqual(a, b)
    }

    func testNoPlaintextOrTempFilesLeftBehind() throws {
        let s = store(); let id = UUID()
        try s.save(id: id, body: "sk-secret-123")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names, ["\(id.uuidString).enc"])
    }

    func testDeleteRemovesFile() throws {
        let s = store(); let id = UUID()
        try s.save(id: id, body: "x")
        try s.delete(id: id)
        XCTAssertEqual(try s.allIDs(), [])
        XCTAssertThrowsError(try s.load(id: id))
    }
}
