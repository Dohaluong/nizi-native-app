import Foundation
import Photos
import SwiftData

@MainActor
@Observable
final class NiziMoveImportCoordinator {
    enum Screen: Equatable { case introduction, scanner, confirmation, progress, result }
    private let api = NiziMoveAPI()
    private let modelContainer: ModelContainer
    private var manifest: NiziMoveManifest?
    private var sessionID: String?
    private var task: Task<Void, Never>?
    var screen: Screen = .introduction
    var errorMessage: String?
    var completedCount = 0
    var failedCount = 0
    var totalCount = 0
    var totalBytes: Int64 = 0
    var savedBytes: Int64 = 0
    var isPaused = false

    init(modelContainer: ModelContainer) { self.modelContainer = modelContainer }

    /// Restores a persisted, non-terminal session without ever using the one-time QR token again.
    func restoreMostRecentIfNeeded() async {
        do {
            let store = NiziMoveImportStore(modelContainer: modelContainer)
            guard let restoredID = try await store.mostRecentResumableSessionID(),
                  let token = try NiziMoveKeychain.accessToken(sessionID: restoredID)
            else { return }
            let fetched = try await api.manifest(sessionID: restoredID, accessToken: token)
            try await store.saveManifest(fetched)
            manifest = fetched; sessionID = restoredID; totalCount = fetched.assets.count; totalBytes = fetched.assets.reduce(0) { $0 + $1.byteSize }
            let snapshots = try await store.assetSnapshots(sessionID: restoredID)
            completedCount = snapshots.filter { $0.status == .serverAcknowledged }.count
            failedCount = snapshots.filter { $0.status == .failed }.count
            screen = .confirmation
        } catch {
            // A failed best-effort restore must never block opening the Import screen. The user
            // can still scan a fresh QR; persisted history remains available for diagnostics.
            NiziLogger.discovery.error("move_import_restore_failed")
        }
    }

    func receive(qr: NiziMoveQR) async {
        do {
            let token: String
            if let existing = try NiziMoveKeychain.accessToken(sessionID: qr.sessionID) { token = existing }
            else { token = try await api.claim(qr); try NiziMoveKeychain.save(accessToken: token, sessionID: qr.sessionID) }
            let fetched = try await api.manifest(sessionID: qr.sessionID, accessToken: token)
            try await NiziMoveImportStore(modelContainer: modelContainer).saveManifest(fetched)
            manifest = fetched; sessionID = qr.sessionID; totalCount = fetched.assets.count; totalBytes = fetched.assets.reduce(0) { $0 + $1.byteSize }
            screen = .confirmation
        } catch { errorMessage = error.localizedDescription; screen = .introduction }
    }

    func start() async {
        guard let manifest, let sessionID else { return }
        let access = PhotoKitAuthorizationService()
        let status = await access.currentStatus()
        let granted = status == .full ? status : await access.requestAccess()
        guard granted == .full else { errorMessage = NiziMoveError.photosPermission.localizedDescription; return }
        guard availableStorage() >= manifest.assets.reduce(0, { $0 + $1.byteSize }) else { errorMessage = NiziMoveError.insufficientStorage.localizedDescription; return }
        screen = .progress; isPaused = false
        task?.cancel()
        task = Task { [weak self] in await self?.run(sessionID: sessionID) }
    }

    func pause() { isPaused = true; task?.cancel(); Task { [modelContainer, sessionID] in if let sessionID { try? await NiziMoveImportStore(modelContainer: modelContainer).updateSession(sessionID, status: .paused) } } }
    func cancel() { pause(); screen = .introduction }

    private func run(sessionID: String) async {
        let store = NiziMoveImportStore(modelContainer: modelContainer)
        do {
            guard let token = try NiziMoveKeychain.accessToken(sessionID: sessionID) else { throw NiziMoveError.expired }
            try await store.updateSession(sessionID, status: .importing)
            let assets = try await store.assetSnapshots(sessionID: sessionID)
            for record in assets where record.status != .serverAcknowledged && record.status != .failed && !Task.isCancelled {
                try await processWithRetries(record, sessionID: sessionID, token: token, store: store)
            }
            guard !Task.isCancelled else { return }
            let final = try await store.assetSnapshots(sessionID: sessionID)
            if final.allSatisfy({ $0.status == .serverAcknowledged || $0.status == .failed || $0.status == .skipped }) {
                try await api.complete(sessionID: sessionID, accessToken: token)
                NiziMoveKeychain.delete(sessionID: sessionID)
                try await store.updateSession(sessionID, status: final.contains(where: { $0.status == .failed }) ? .partiallyCompleted : .completed)
                screen = .result
            }
        } catch { errorMessage = error.localizedDescription; try? await store.updateSession(sessionID, status: .partiallyCompleted); screen = .progress }
    }

    private func processWithRetries(_ initial: NiziMoveStoredAsset, sessionID: String, token: String, store: NiziMoveImportStore) async throws {
        var record = initial
        for attempt in 0..<3 {
            do {
                try await process(record, sessionID: sessionID, token: token, store: store)
                return
            } catch is CancellationError { throw CancellationError() }
            catch {
                if attempt == 2 { try await fail(record, token: token, store: store, reason: "IMPORT_FAILED"); return }
                try await store.incrementRetry(for: record.assetID)
                // Re-read after every failed attempt. A crash/network loss after Photos succeeds
                // leaves a localIdentifier in SwiftData, so the next attempt only indexes/acks.
                if let saved = try await store.assetSnapshots(sessionID: sessionID).first(where: { $0.assetID == record.assetID }) { record = saved }
            }
        }
    }

    private func process(_ record: NiziMoveStoredAsset, sessionID: String, token: String, store: NiziMoveImportStore) async throws {
        let asset = manifest?.assets.first(where: { $0.assetID == record.assetID }) ?? record.manifestAsset
        try await store.updateSession(sessionID, status: .importing, currentAssetID: record.assetID)
        var localIdentifier = record.phAssetLocalIdentifier
        if localIdentifier == nil {
            try await store.updateAsset(record.assetID, status: .downloading)
            let source = try await api.download(asset, accessToken: token)
            let file = try temporaryURL(assetID: record.assetID, filename: record.filename)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: source, to: file)
            try await store.updateAsset(record.assetID, status: .downloaded, temporaryFilePath: file.path)
            guard try NiziMovePhotoSaver.sha256(of: file).caseInsensitiveCompare(record.sha256) == .orderedSame else {
                try? FileManager.default.removeItem(at: file)
                throw NiziMoveError.server("CHECKSUM_MISMATCH")
            }
            try await store.updateAsset(record.assetID, status: .verified)
            try await store.updateAsset(record.assetID, status: .savingToPhotos)
            localIdentifier = try await NiziMovePhotoSaver.save(fileURL: file, metadata: asset)
            try await store.updateAsset(record.assetID, status: .savedToPhotos, localIdentifier: localIdentifier)
        }
        guard let localIdentifier else { return }
        try await index(localIdentifier: localIdentifier)
        try await store.updateAsset(record.assetID, status: .indexed)
        try await api.acknowledge(assetID: record.assetID, accessToken: token)
        try await store.updateAsset(record.assetID, status: .serverAcknowledged)
        if let path = record.temporaryFilePath { try? FileManager.default.removeItem(atPath: path) }
        completedCount += 1; savedBytes += record.byteSize
    }

    private func fail(_ record: NiziMoveStoredAsset, token: String, store: NiziMoveImportStore, reason: String) async throws {
        try? await api.acknowledge(assetID: record.assetID, accessToken: token, failedReason: reason)
        try await store.updateAsset(record.assetID, status: .failed, errorCode: reason, incrementRetry: true)
        failedCount += 1
    }

    private func index(localIdentifier: String) async throws {
        let provider = PhotoKitAssetProvider()
        let records = provider.fetchAssetRecords(localIdentifiers: [localIdentifier])
        guard records.count == 1 else { throw NiziMoveError.photosPermission }
        try await SwiftDataMemoryDiscoveryStore(modelContainer: modelContainer).upsert(records)
    }

    private func temporaryURL(assetID: String, filename: String) throws -> URL {
        guard assetID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw NiziMoveError.invalidManifest }
        let ext = URL(fileURLWithPath: filename).pathExtension.filter { $0.isLetter || $0.isNumber }
        return FileManager.default.temporaryDirectory.appendingPathComponent(assetID).appendingPathExtension(ext.isEmpty ? "img" : ext)
    }

    private func availableStorage() -> Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
