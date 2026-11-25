import XCTest
@testable import StickyCore

final class FolderMigratorTests: XCTestCase {
    var root: URL!, src: URL!, dst: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        src = root.appendingPathComponent("src"); dst = root.appendingPathComponent("dst")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func write(_ name: String, in dir: URL, _ text: String = "x") throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func names(_ dir: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() }

    func testMovesOnlyMdAndChangeLog() throws {
        try write("a-111111.md", in: src); try write("changes.jsonl", in: src); try write("photo.png", in: src)
        try FolderMigrator.move(from: src, to: dst)
        XCTAssertEqual(names(dst), ["a-111111.md", "changes.jsonl"])
        XCTAssertEqual(names(src), ["photo.png"])
    }

    func testCollisionThrowsAndMovesNothing() throws {
        try write("a-111111.md", in: src, "mine"); try write("b-222222.md", in: src)
        try write("b-222222.md", in: dst, "theirs")
        XCTAssertThrowsError(try FolderMigrator.move(from: src, to: dst))
        XCTAssertEqual(names(src), ["a-111111.md", "b-222222.md"])
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("b-222222.md"), encoding: .utf8), "theirs")
        XCTAssertEqual(names(dst), ["b-222222.md"])
    }

    func testMissingSourceThrows() {
        XCTAssertThrowsError(try FolderMigrator.move(from: root.appendingPathComponent("nope"), to: dst))
    }
}
