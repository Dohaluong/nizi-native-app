import Foundation
import XCTest
@testable import Nizi

final class GoogleDriveShareImportModelsTests: XCTestCase {
    func testRelativeThumbnailIsResolvedOnlyAgainstNiziMove() {
        let item = GoogleDriveInspectionItem(
            itemId: "opaque-item", name: "ảnh.heic", mimeType: "image/heic", size: 42,
            width: 10, height: 20, modifiedTime: nil, thumbnailUrl: URL(string: "/api/google-drive-share/previews/token"), canDownload: true
        )

        let resolved = item.resolvingThumbnailURL(against: URL(string: "https://move.nizi.vn")!)

        XCTAssertEqual(resolved.thumbnailUrl?.absoluteString, "https://move.nizi.vn/api/google-drive-share/previews/token")
        XCTAssertEqual(resolved.itemId, item.itemId)
    }

    func testAbsoluteThumbnailIsNotRewritten() {
        let item = GoogleDriveInspectionItem(
            itemId: "opaque-item", name: "ảnh.jpg", mimeType: "image/jpeg", size: 42,
            width: nil, height: nil, modifiedTime: nil, thumbnailUrl: URL(string: "https://move.nizi.vn/api/google-drive-share/previews/token")!, canDownload: true
        )

        XCTAssertEqual(item.resolvingThumbnailURL(against: URL(string: "https://move.nizi.vn")!).thumbnailUrl, item.thumbnailUrl)
    }
}
