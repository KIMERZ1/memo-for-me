import XCTest
@testable import StickyCore

final class FolderAccessTests: XCTestCase {
    var root: URL!
    var defaults: UserDefaults!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    func testStartsOnDefaultFolder() throws {
        let def = root.appendingPathComponent("default")
        let fa = FolderAccess(defaults: defaults, defaultFolder: def)
        XCTAssertEqual(fa.status, .usingDefault)
        let used = try fa.withAccess { $0 }
        XCTAssertEqual(used.standardizedFileURL, def.standardizedFileURL)
        XCTAssertTrue(fm.fileExists(atPath: def.path))
    }

    func testSetFolderThenOk() throws {
        let chosen = root.appendingPathComponent("chosen")
        try fm.createDirectory(at: chosen, withIntermediateDirectories: true)
        let fa = FolderAccess(defaults: defaults, defaultFolder: root.appendingPathComponent("d"))
        try fa.setFolder(chosen)
        XCTAssertEqual(fa.status, .ok)
        XCTAssertEqual(fa.currentFolder.standardizedFileURL.path, chosen.standardizedFileURL.path)
        XCTAssertEqual(FolderAccess(defaults: defaults, defaultFolder: root).status, .ok)
    }

    func testDeletedFolderReportsMissingAndWithAccessThrows() throws {
        let chosen = root.appendingPathComponent("chosen")
        try fm.createDirectory(at: chosen, withIntermediateDirectories: true)
        let fa = FolderAccess(defaults: defaults, defaultFolder: root.appendingPathComponent("d"))
        try fa.setFolder(chosen)
        try fm.removeItem(at: chosen)
        XCTAssertEqual(fa.status, .missing)
        XCTAssertThrowsError(try fa.withAccess { $0 })
    }

    func testGarbageBookmarkReportsPermissionLost() {
        defaults.set(Data([1, 2, 3]), forKey: FolderAccess.bookmarkKey)
        let fa = FolderAccess(defaults: defaults, defaultFolder: root)
        XCTAssertEqual(fa.status, .permissionLost)
    }

    func testOpenFolderReturnsFolderAndThrowsWhenMissing() throws {
        let chosen = root.appendingPathComponent("chosen")
        try fm.createDirectory(at: chosen, withIntermediateDirectories: true)
        let fa = FolderAccess(defaults: defaults, defaultFolder: root.appendingPathComponent("d"))
        try fa.setFolder(chosen)
        let opened = try fa.openFolder()
        XCTAssertEqual(opened.standardizedFileURL.path, chosen.standardizedFileURL.path)
        fa.closeFolder()
        try fm.removeItem(at: chosen)
        XCTAssertThrowsError(try fa.openFolder())
    }
}
