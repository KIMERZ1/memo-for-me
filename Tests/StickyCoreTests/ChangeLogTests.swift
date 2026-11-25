import XCTest
@testable import StickyCore

final class ChangeLogTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testAppendsOneValidJSONLinePerEvent() throws {
        let log = ChangeLog(folder: dir, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let note = Note(id: UUID(), created: Date(), body: "제목\n본문 비밀아님")
        try log.append(event: .created, note: note, file: "제목-abc123.md")
        try log.append(event: .updated, note: note, file: "제목-abc123.md")
        let lines = try String(contentsOf: dir.appendingPathComponent("changes.jsonl"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        let obj = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        XCTAssertEqual(Set(obj.keys), ["v", "ts", "event", "id", "file", "title"])
        XCTAssertEqual(obj["v"] as? Int, 1)            // contract version (docs/NOTE-APP-INTEGRATION-GUIDE.md)
        XCTAssertEqual(obj["event"] as? String, "created")
        XCTAssertEqual(obj["title"] as? String, "제목")
        XCTAssertEqual(obj["id"] as? String, note.id.uuidString)
        XCTAssertFalse(lines[0].contains("본문"))
    }
}
