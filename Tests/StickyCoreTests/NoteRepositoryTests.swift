import XCTest
@testable import StickyCore

final class NoteRepositoryTests: XCTestCase {
    var dir: URL!
    var repo: NoteRepository!
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        repo = NoteRepository(folder: dir, now: { [t0] in t0 })
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func mdFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".md") }.sorted()
    }
    private func logEvents() throws -> [String] {
        let url = dir.appendingPathComponent("changes.jsonl")
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").map {
            (try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any])["event"] as! String
        }
    }

    func testSaveCreatesMdWithFrontMatterOnly3Keys() throws {
        let note = Note(id: UUID(), created: t0, body: "기말고사 일정\n12/6")
        let url = try repo.save(note)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "---")
        XCTAssertEqual(lines[1], "id: \(note.id.uuidString)")
        XCTAssertTrue(lines[2].hasPrefix("created: "))
        XCTAssertEqual(lines[3], "type: note")
        XCTAssertEqual(lines[4], "---")
        XCTAssertEqual(lines[5...].joined(separator: "\n"), "기말고사 일정\n12/6")
    }

    func testSaveThenLoadRoundTrip() throws {
        let note = Note(id: UUID(), created: t0, body: "a\n\nb")
        _ = try repo.save(note)
        let loaded = try repo.load(id: note.id)
        XCTAssertEqual(loaded.body, "a\n\nb")
        XCTAssertEqual(loaded.created, t0)
    }

    func testTitleChangeRenamesFileKeepsId() throws {
        var note = Note(id: UUID(), created: t0, body: "첫제목")
        _ = try repo.save(note)
        note.body = "바뀐제목"
        _ = try repo.save(note)
        let files = try mdFiles()
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasPrefix("바뀐제목-"))
        XCTAssertEqual(try repo.load(id: note.id).body, "바뀐제목")
    }

    func testEventsCreatedUpdatedDeleted() throws {
        var note = Note(id: UUID(), created: t0, body: "x")
        _ = try repo.save(note)
        note.body = "xy"
        _ = try repo.save(note)
        try repo.delete(id: note.id)
        XCTAssertEqual(try logEvents(), ["created", "updated", "deleted"])
        XCTAssertEqual(try mdFiles(), [])
    }

    func testIdenticalResaveWritesNoEvent() throws {
        let note = Note(id: UUID(), created: t0, body: "x")
        _ = try repo.save(note)
        _ = try repo.save(note)
        XCTAssertEqual(try logEvents(), ["created"])
    }

    func testExternalEditIsSeenOnLoad() throws {
        let note = Note(id: UUID(), created: t0, body: "원본")
        let url = try repo.save(note)
        let edited = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "원본", with: "외부수정")
        try edited.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try repo.load(id: note.id).body, "외부수정")
    }

    func testLoadAllIgnoresNonMdAndBrokenFrontMatter() throws {
        let good = Note(id: UUID(), created: t0, body: "good")
        _ = try repo.save(good)
        try "no front matter".write(to: dir.appendingPathComponent("broken.md"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        let all = try repo.loadAll()
        XCTAssertEqual(all.map(\.id), [good.id])
    }

    func testSameTitleNotesGetDistinctFiles() throws {
        _ = try repo.save(Note(id: UUID(), created: t0, body: "같은 제목"))
        _ = try repo.save(Note(id: UUID(), created: t0, body: "같은 제목"))
        XCTAssertEqual(try mdFiles().count, 2)
    }

    func testTitleIsFirstNonEmptyLineWithoutMarkdown() {
        XCTAssertEqual(Note(id: UUID(), created: t0, body: "\n\n**굵게** 제목\n다음").title, "굵게 제목")
        XCTAssertEqual(Note(id: UUID(), created: t0, body: "  \n").title, "제목 없음")
    }

    func testNameIsSavedInFrontMatterAndRoundTrips() throws {
        let note = Note(id: UUID(), created: t0, body: "본문", name: "기말고사 일정")
        let url = try repo.save(note)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\nname: 기말고사 일정\n"))
        XCTAssertEqual(try repo.load(id: note.id).name, "기말고사 일정")
        XCTAssertEqual(try repo.load(id: note.id).body, "본문")
    }

    func testNoNameKeyWhenNameEmpty() throws {
        let url = try repo.save(Note(id: UUID(), created: t0, body: "x"))
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("name:"))
    }

    func testTitleUsesNameWhenSetElseFirstLine() {
        XCTAssertEqual(Note(id: UUID(), created: t0, body: "첫 줄", name: "내 이름").title, "내 이름")
        XCTAssertEqual(Note(id: UUID(), created: t0, body: "첫 줄", name: "  ").title, "첫 줄")
    }

    func testNameChangeRenamesFileAndLogsUpdate() throws {
        var note = Note(id: UUID(), created: t0, body: "본문", name: "하나")
        _ = try repo.save(note)
        note.name = "둘"
        _ = try repo.save(note)
        let files = try mdFiles()
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasPrefix("둘-"))
        XCTAssertEqual(try logEvents(), ["created", "updated"])
    }

    func testNameWithColonAndNewlineRoundTripsOnOneLine() throws {
        let note = Note(id: UUID(), created: t0, body: "b", name: "a: b\nc")
        _ = try repo.save(note)
        XCTAssertEqual(try repo.load(id: note.id).name, "a: b c")
    }
}
