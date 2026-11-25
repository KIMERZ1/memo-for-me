import XCTest
@testable import StickyCore

final class SmokeTests: XCTestCase {
    func testCoreVersion() {
        XCTAssertEqual(StickyCoreInfo.version, "0.1.0")
    }
}
