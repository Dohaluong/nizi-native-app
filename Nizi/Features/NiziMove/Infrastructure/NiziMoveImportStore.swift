import Foundation
import SwiftData

@ModelActor
actor NiziMoveImportStore {
    func saveManifest(_ manifest: NiziMoveManifest) throws {
        let sessionID = manifest.sessionID
        var sessionFetch = FetchDescriptor<MDNiziMoveImportSession>(predicate: #Predicate { $0.sessionID == sessionID })
        sessionFetch.fetchLimit = 1
        let session = try modelContext.fetch(sessionFetch).first ?? {
            let value = MDNiziMoveImportSession(manifest: manifest)
            modelContext.insert(value)
            return value
        }()
        session.protocolVersion = manifest.protocolVersion
        session.expiresAt = manifest.expiresAt
        session.assetCount = manifest.assets.count
        session.totalBytes = manifest.assets.reduce(0) { $0 + $1.byteSize }
        for asset in manifest.assets {
            // `#Predicate` can capture scalar values, but not a member access on the manifest
            // struct itself (SwiftData cannot serialize that expression for its query graph).
            let assetID = asset.assetID
            var fetch = FetchDescriptor<MDNiziMoveImportAsset>(predicate: #Predicate { $0.assetID == assetID })
            fetch.fetchLimit = 1
            if try modelContext.fetch(fetch).first == nil { modelContext.insert(MDNiziMoveImportAsset(asset: asset, sessionID: sessionID)) }
        }
        try modelContext.save()
    }

    private func session(sessionID: String) throws -> MDNiziMoveImportSession? {
        try modelContext.fetch(FetchDescriptor<MDNiziMoveImportSession>(predicate: #Predicate { $0.sessionID == sessionID })).first
    }

    private func assets(sessionID: String) throws -> [MDNiziMoveImportAsset] {
        try modelContext.fetch(FetchDescriptor<MDNiziMoveImportAsset>(predicate: #Predicate { $0.sessionID == sessionID }, sortBy: [SortDescriptor(\.assetID)]))
    }

    func assetSnapshots(sessionID: String) throws -> [NiziMoveStoredAsset] { try assets(sessionID: sessionID).map(NiziMoveStoredAsset.init) }

    func mostRecentResumableSessionID() throws -> String? {
        let terminal: Set<String> = [NiziMoveSessionStatus.completed.rawValue, NiziMoveSessionStatus.cancelled.rawValue, NiziMoveSessionStatus.expired.rawValue]
        return try modelContext.fetch(FetchDescriptor<MDNiziMoveImportSession>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            .first(where: { !terminal.contains($0.status) })?.sessionID
    }

    func updateAsset(_ assetID: String, status: NiziMoveAssetStatus, temporaryFilePath: String? = nil, localIdentifier: String? = nil, errorCode: String? = nil, incrementRetry: Bool = false) throws {
        guard let asset = try modelContext.fetch(FetchDescriptor<MDNiziMoveImportAsset>(predicate: #Predicate { $0.assetID == assetID })).first else { return }
        asset.status = status.rawValue
        if let temporaryFilePath { asset.temporaryFilePath = temporaryFilePath }
        if let localIdentifier { asset.phAssetLocalIdentifier = localIdentifier }
        if let errorCode { asset.lastErrorCode = errorCode }
        if incrementRetry { asset.retryCount += 1 }
        try modelContext.save()
    }

    func incrementRetry(for assetID: String) throws {
        guard let asset = try modelContext.fetch(FetchDescriptor<MDNiziMoveImportAsset>(predicate: #Predicate { $0.assetID == assetID })).first else { return }
        asset.retryCount += 1
        try modelContext.save()
    }

    func updateSession(_ sessionID: String, status: NiziMoveSessionStatus, currentAssetID: String? = nil) throws {
        guard let session = try session(sessionID: sessionID) else { return }
        session.status = status.rawValue
        session.currentAssetID = currentAssetID
        let all = try assets(sessionID: sessionID)
        session.completedCount = all.filter { $0.status == NiziMoveAssetStatus.serverAcknowledged.rawValue }.count
        session.failedCount = all.filter { $0.status == NiziMoveAssetStatus.failed.rawValue }.count
        try modelContext.save()
    }
}

struct NiziMoveStoredAsset: Sendable {
    let assetID: String; let filename: String; let mimeType: String; let byteSize: Int64; let sha256: String
    let capturedAt: Date?; let latitude: Double?; let longitude: Double?; let relativePath: String?
    let status: NiziMoveAssetStatus; let temporaryFilePath: String?; let phAssetLocalIdentifier: String?; let retryCount: Int

    init(_ model: MDNiziMoveImportAsset) {
        assetID = model.assetID; filename = model.filename; mimeType = model.mimeType; byteSize = model.byteSize; sha256 = model.sha256
        capturedAt = model.capturedAt; latitude = model.latitude; longitude = model.longitude; relativePath = model.relativePath
        status = NiziMoveAssetStatus(rawValue: model.status) ?? .failed; temporaryFilePath = model.temporaryFilePath
        phAssetLocalIdentifier = model.phAssetLocalIdentifier; retryCount = model.retryCount
    }

    var manifestAsset: NiziMoveManifestAsset {
        NiziMoveManifestAsset(assetID: assetID, filename: filename, mimeType: mimeType, byteSize: byteSize, sha256: sha256, downloadURL: URL(string: "https://move.nizi.vn")!, capturedAt: capturedAt, latitude: latitude, longitude: longitude, relativePath: relativePath)
    }
}
