import XCTest
import AppKit
@testable import StickyCore

final class BackgroundImageStoreTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default
    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func makePNG(width: Int, height: Int, name: String = "src.png") throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let url = root.appendingPathComponent(name)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }
    private func store() -> BackgroundImageStore { BackgroundImageStore(directory: root.appendingPathComponent("bg")) }

    func testImportCopiesAndSurvivesOriginalDeletion() throws {
        let src = try makePNG(width: 100, height: 80)
        let s = store()
        let name = try s.importImage(from: src)
        try fm.removeItem(at: src)
        XCTAssertTrue(fm.fileExists(atPath: s.url(for: name).path))
    }

    func testNonImageThrows() throws {
        let txt = root.appendingPathComponent("a.txt")
        try "hello".write(to: txt, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store().importImage(from: txt))
    }

    func testLargeImageDownscaledToLongSide1200() throws {
        let src = try makePNG(width: 3000, height: 1500)
        let s = store()
        let name = try s.importImage(from: src)
        let rep = NSBitmapImageRep(data: try Data(contentsOf: s.url(for: name)))!
        XCTAssertEqual(max(rep.pixelsWide, rep.pixelsHigh), 1200)
    }

    func testSmallImageKeptAtOriginalSize() throws {
        let src = try makePNG(width: 300, height: 200)
        let s = store()
        let name = try s.importImage(from: src)
        let rep = NSBitmapImageRep(data: try Data(contentsOf: s.url(for: name)))!
        XCTAssertEqual(rep.pixelsWide, 300)
    }

    func testSameSourceTwiceGetsUniqueNames() throws {
        let src = try makePNG(width: 50, height: 50)
        let s = store()
        XCTAssertNotEqual(try s.importImage(from: src), try s.importImage(from: src))
    }

    func testRemoveDeletesFile() throws {
        let s = store()
        let name = try s.importImage(from: try makePNG(width: 50, height: 50))
        s.remove(name)
        XCTAssertFalse(fm.fileExists(atPath: s.url(for: name).path))
    }
}
