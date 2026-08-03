import CoreLocation
import CryptoKit
import Foundation
import Photos

enum NiziMovePhotoSaver {
    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func save(fileURL: URL, metadata: NiziMoveManifestAsset) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var identifier: String?
            PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL) else { return }
                request.creationDate = metadata.capturedAt
                if let latitude = metadata.latitude, let longitude = metadata.longitude { request.location = CLLocation(latitude: latitude, longitude: longitude) }
                identifier = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                if success, let identifier { continuation.resume(returning: identifier) }
                else { continuation.resume(throwing: error ?? NiziMoveError.server("PHOTO_SAVE_FAILED")) }
            }
        }
    }
}
