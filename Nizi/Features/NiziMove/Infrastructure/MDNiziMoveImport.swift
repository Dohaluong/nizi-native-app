import Foundation
import SwiftData

@Model
final class MDNiziMoveImportSession {
    @Attribute(.unique) var sessionID: String
    var protocolVersion: Int
    var status: String
    var createdAt: Date
    var expiresAt: Date
    var assetCount: Int
    var totalBytes: Int64
    var completedCount: Int
    var failedCount: Int
    var currentAssetID: String?
    /// Keychain account identifier only; credentials are never stored in SwiftData.
    var keychainTokenReference: String

    init(manifest: NiziMoveManifest) {
        sessionID = manifest.sessionID
        protocolVersion = manifest.protocolVersion
        status = NiziMoveSessionStatus.ready.rawValue
        createdAt = Date()
        expiresAt = manifest.expiresAt
        assetCount = manifest.assets.count
        totalBytes = manifest.assets.reduce(0) { $0 + $1.byteSize }
        completedCount = 0
        failedCount = 0
        currentAssetID = nil
        keychainTokenReference = manifest.sessionID
    }
}

@Model
final class MDNiziMoveImportAsset {
    @Attribute(.unique) var assetID: String
    var sessionID: String
    var filename: String
    var mimeType: String
    var byteSize: Int64
    var sha256: String
    var capturedAt: Date?
    var latitude: Double?
    var longitude: Double?
    var relativePath: String?
    var status: String
    var temporaryFilePath: String?
    var phAssetLocalIdentifier: String?
    var retryCount: Int
    var lastErrorCode: String?

    init(asset: NiziMoveManifestAsset, sessionID: String) {
        assetID = asset.assetID
        self.sessionID = sessionID
        filename = asset.filename
        mimeType = asset.mimeType
        byteSize = asset.byteSize
        sha256 = asset.sha256
        capturedAt = asset.capturedAt
        latitude = asset.latitude
        longitude = asset.longitude
        relativePath = asset.relativePath
        status = NiziMoveAssetStatus.pending.rawValue
        temporaryFilePath = nil
        phAssetLocalIdentifier = nil
        retryCount = 0
        lastErrorCode = nil
    }
}
