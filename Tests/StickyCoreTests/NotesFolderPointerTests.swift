import XCTest
@testable import StickyCore

final class NotesFolderPointerTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testWritesTheAbsolutePathAsOneLine() throws {
        let pointer = NotesFolderPointer(fileURL: dir.appendingPathComponent("data/notes-folder.txt"))
        let folder = dir.appendingPathComponent("내 메모 폴더")
        try pointer.write(folder: folder)                                   // also creates the data folder
        let text = try String(contentsOf: pointer.fileURL, encoding: .utf8)
        XCTAssertEqual(text, folder.path + "\n")
    }

    func testRewritingReplacesTheContentAndLeavesNoTempFiles() throws {
        let pointer = NotesFolderPointer(fileURL: dir.appendingPathComponent("notes-folder.txt"))
        try pointer.write(folder: dir.appendingPathComponent("a"))
        try pointer.write(folder: dir.appendingPathComponent("b"))
        XCTAssertEqual(try String(contentsOf: pointer.fileURL, encoding: .utf8), dir.appendingPathComponent("b").path + "\n")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["notes-folder.txt"])
    }

    func testSourceMarkerIsCreatedOnceWithTheContractFields() throws {
        let folder = dir.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try NotesFolderPointer.sourceMarker(folder: folder, appVersion: "1.0.0")
        let url = folder.appendingPathComponent("sticky-source.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertEqual(Set(obj.keys), ["app", "app_version", "contract", "feed"])
        XCTAssertEqual(obj["contract"] as? Int, 1)
        XCTAssertEqual(obj["feed"] as? String, "changes.jsonl")
        XCTAssertEqual(obj["app_version"] as? String, "1.0.0")
        let before = try Data(contentsOf: url)
        try NotesFolderPointer.sourceMarker(folder: folder, appVersion: "9.9.9")   // already there: left alone
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testSourceMarkerFailsForAMissingFolder() {
        XCTAssertThrowsError(try NotesFolderPointer.sourceMarker(folder: dir.appendingPathComponent("nope"), appVersion: "1"))
    }
}
