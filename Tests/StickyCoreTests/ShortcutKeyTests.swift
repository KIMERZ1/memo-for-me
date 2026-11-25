import XCTest
@testable import StickyCore

final class ShortcutKeyTests: XCTestCase {
    func testEditingKeysByPhysicalKeyCode() {
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 8), "c")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 9), "v")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 7), "x")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 0), "a")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 6), "z")
    }
    func testFormattingAndWindowKeys() {
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 11), "b")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 34), "i")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 32), "u")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 45), "n")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 13), "w")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 24), "=")
        XCTAssertEqual(ShortcutKey.name(forKeyCode: 27), "-")
    }
    func testUnknownKeyCodeIsNil() {
        XCTAssertNil(ShortcutKey.name(forKeyCode: 53))
    }
}
