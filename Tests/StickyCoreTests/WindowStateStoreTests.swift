import XCTest
@testable import StickyCore

final class WindowStateStoreTests: XCTestCase {
    var dir: URL!
    var file: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("state.json")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func state(_ id: UUID = UUID(), color: NoteColor = .yellow) -> NoteWindowState {
        NoteWindowState(noteID: id, isSecure: false, frame: CGRect(x: 10, y: 20, width: 280, height: 300),
                        colorName: color, backgroundImageFile: nil, isPinnedHere: false, floatsOnTop: false)
    }

    func testRoundTripAcrossInstances() throws {
        let s = state()
        let a = WindowStateStore(fileURL: file)
        a.update(s); a.flush()
        XCTAssertEqual(WindowStateStore(fileURL: file).all(), [s])
    }

    func testUpdateOverwritesSameNote() {
        let id = UUID()
        let store = WindowStateStore(fileURL: file)
        store.update(state(id, color: .yellow))
        store.update(state(id, color: .blue))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all()[0].colorName, .blue)
    }

    func testRemove() {
        let id = UUID()
        let store = WindowStateStore(fileURL: file)
        store.update(state(id)); store.remove(noteID: id)
        XCTAssertEqual(store.all(), [])
    }

    func testCorruptFileStartsEmptyAndKeepsBackup() throws {
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)
        let store = WindowStateStore(fileURL: file)
        XCTAssertEqual(store.all(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json.bak").path))
    }

    func testStateFileNeverContainsNoteBody() throws {
        let store = WindowStateStore(fileURL: file)
        store.update(state()); store.flush()
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains("body"))
    }

    func testIsOpenDefaultsToTrueAndOldFilesStillDecode() throws {
        XCTAssertTrue(state().isOpen)
        let id = UUID()
        let old = """
        [{"noteID":"\(id.uuidString)","isSecure":false,"frame":[[1,2],[3,4]],"colorName":"blue",
          "backgroundImageFile":null,"isPinnedHere":false,"floatsOnTop":true}]
        """
        try old.write(to: file, atomically: true, encoding: .utf8)
        let loaded = WindowStateStore(fileURL: file).all()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(loaded[0].isOpen)
    }

    func testClosedStatePersists() {
        var s = state(); s.isOpen = false
        let a = WindowStateStore(fileURL: file); a.update(s)
        XCTAssertFalse(WindowStateStore(fileURL: file).all()[0].isOpen)
    }
}
