import XCTest
@testable import StickyCore

final class SecurePayloadTests: XCTestCase {
    func testRoundTripKeepsNameAndBody() {
        let p = SecurePayload(name: "API 키", body: "sk-123\n두번째 줄")
        XCTAssertEqual(SecurePayload.decode(p.encoded()), p)
    }

    func testLegacyPlainBodyDecodesWithEmptyName() {
        XCTAssertEqual(SecurePayload.decode("그냥 본문\n입니다"), SecurePayload(name: "", body: "그냥 본문\n입니다"))
    }

    func testPlainTextThatLooksLikeJSONIsNotMistakenForPayload() {
        let tricky = "{\"name\":\"x\",\"body\":\"y\"}"
        XCTAssertEqual(SecurePayload.decode(tricky), SecurePayload(name: "", body: tricky))
    }
}
