import XCTest
@testable import Nizi

final class NiziMoveQRTests: XCTestCase {
    func testAcceptsTrustedHTTPSMoveURL() throws {
        let qr = try parseNiziMoveQR("https://move.nizi.vn/import/imp_123?token=one-time")
        XCTAssertEqual(qr.sessionID, "imp_123")
        XCTAssertEqual(qr.pairingToken, "one-time")
    }

    func testRejectsUntrustedOrMalformedURLs() {
        [
            "http://move.nizi.vn/import/imp_123?token=x",
            "https://evil.example/import/imp_123?token=x",
            "https://move.nizi.vn:443/import/imp_123?token=x",
            "https://move.nizi.vn/import/123?token=x",
            "https://move.nizi.vn/import/imp_123"
        ].forEach { value in
            XCTAssertThrowsError(try parseNiziMoveQR(value))
        }
    }
}
