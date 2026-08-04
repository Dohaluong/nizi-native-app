import Foundation
import XCTest
@testable import Nizi

final class NiziMoveManifestCompatibilityTests: XCTestCase {
    func testDecodesGoogleDriveSourceTypeWithoutChangingAssetProtocol() throws {
        let manifest = try decodeManifest(sourceTypeField: #""sourceType":"google_drive_share","#)

        XCTAssertEqual(manifest.sourceType, "google_drive_share")
        XCTAssertEqual(manifest.assets.count, 1)
        XCTAssertEqual(manifest.assets[0].downloadURL.host, "move.nizi.vn")
    }

    func testDecodesExistingManifestWhenSourceTypeIsAbsent() throws {
        let manifest = try decodeManifest(sourceTypeField: "")

        XCTAssertNil(manifest.sourceType)
        XCTAssertEqual(manifest.sessionID, "imp_compatibility")
    }

    private func decodeManifest(sourceTypeField: String) throws -> NiziMoveManifest {
        let json = """
        {
          "protocolVersion": 1,
          "sessionId": "imp_compatibility",
          "status": "claimed",
          \(sourceTypeField)
          "expiresAt": "2026-12-01T12:00:00Z",
          "assets": [{
            "assetId": "asset_1",
            "filename": "ảnh gốc.heic",
            "mimeType": "image/heic",
            "byteSize": 12,
            "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "downloadUrl": "https://move.nizi.vn/api/import-assets/asset_1/download"
          }]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ManifestPayload.self, from: Data(json.utf8)).domain()
    }
}
