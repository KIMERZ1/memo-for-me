import XCTest
@testable import StickyCore

final class FileNamingTests: XCTestCase {
    let id = UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890")!

    func testEmptyTitleFallsBack() {
        XCTAssertEqual(FileNaming.fileName(title: "", id: id), "제목 없음-abcdef.md")
    }
    func testForbiddenCharactersReplaced() {
        let n = FileNaming.fileName(title: "a/b:c?d", id: id)
        XCTAssertFalse(n.dropLast(3).contains("/")); XCTAssertFalse(n.contains(":")); XCTAssertFalse(n.contains("?"))
        XCTAssertTrue(n.hasSuffix("-abcdef.md"))
    }
    func testEmojiAllowed() {
        XCTAssertTrue(FileNaming.fileName(title: "장보기 🛒", id: id).hasPrefix("장보기 🛒-"))
    }
    func testLongTitleTruncatedTo60() {
        let n = FileNaming.fileName(title: String(repeating: "가", count: 200), id: id)
        XCTAssertEqual(n, String(repeating: "가", count: 60) + "-abcdef.md")
    }
    func testSameTitleDifferentIdDiffers() {
        XCTAssertNotEqual(FileNaming.fileName(title: "x", id: id), FileNaming.fileName(title: "x", id: UUID()))
    }
    func testLeadingDotsAreStripped() {
        XCTAssertFalse(FileNaming.fileName(title: "..hidden", id: id).hasPrefix("."))
    }
}
