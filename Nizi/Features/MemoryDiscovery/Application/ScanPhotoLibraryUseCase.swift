//
//  ScanPhotoLibraryUseCase.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Batches the whole library into the Local Memory Index, resuming from the last
/// checkpoint on every call. See docs/modules/memory-discovery/ARCHITECTURE.md § 6.3, § 9.
final class ScanPhotoLibraryUseCase {
    private let assetProvider: PhotoAssetProvider
    private let assetRepository: LocalAssetRepository
    private let checkpointRepository: ScanCheckpointRepository
    private let batchSize: Int

    init(
        assetProvider: PhotoAssetProvider,
        assetRepository: LocalAssetRepository,
        checkpointRepository: ScanCheckpointRepository,
        batchSize: Int = 500
    ) {
        self.assetProvider = assetProvider
        self.assetRepository = assetRepository
        self.checkpointRepository = checkpointRepository
        self.batchSize = batchSize
    }

    /// Runs until the scan completes or `pauseFlag` is set between batches. Safe to call again
    /// after a pause, or after the app was relaunched — it always resumes from the saved checkpoint.
    ///
    /// `dateRanges` scopes the scan (see `LibraryScanScope`). It isn't persisted in the checkpoint —
    /// resuming a paused scoped scan means calling `execute` again with the same `dateRanges`, which
    /// the screen that started it is expected to hold onto for its lifetime.
    func execute(
        pauseFlag: ScanPauseFlag,
        dateRanges: [DateRangeFilter] = [],
        onProgress: @escaping (ScanCheckpoint) -> Void,
        onBatch: (([PhotoAssetRecord]) -> Void)? = nil
    ) async throws {
        let total = try await assetProvider.totalAssetCount(dateRanges: dateRanges)
        let scopeKey = ScanCheckpoint.scopeKey(for: dateRanges)
        let libraryVersion = try await libraryVersion(total: total, dateRanges: dateRanges)
        var checkpoint = try await matchingCheckpoint(
            scopeKey: scopeKey, libraryVersion: libraryVersion, total: total
        ) ?? ScanCheckpoint.newInitial()

        checkpoint.scopeKey = scopeKey
        checkpoint.libraryVersion = libraryVersion
        checkpoint.algorithmVersion = ScanCheckpoint.algorithmVersion

        if checkpoint.status == .completed {
            // Persist a legacy checkpoint under its v2 identity before returning, otherwise every
            // launch would have to adopt it again.
            try await checkpointRepository.save(checkpoint)
            onProgress(checkpoint)
            return
        }

        checkpoint.status = .running
        checkpoint.totalAssetsEstimated = total
        checkpoint.updatedAt = Date()
        try await checkpointRepository.save(checkpoint)
        onProgress(checkpoint)

        while checkpoint.cursorOffset < total {
            if pauseFlag.isPauseRequested {
                checkpoint.status = .paused
                checkpoint.updatedAt = Date()
                try await checkpointRepository.save(checkpoint)
                onProgress(checkpoint)
                NiziLogger.discovery.info("scan_paused processed=\(checkpoint.processedCount, privacy: .public)")
                return
            }

            let batch = try await assetProvider.fetchAssetRecords(offset: checkpoint.cursorOffset, limit: batchSize, dateRanges: dateRanges)
            if batch.isEmpty { break }
            onBatch?(batch)

            let result = try await assetRepository.upsert(batch)
            checkpoint.processedCount += result.succeededCount
            checkpoint.failedCount += result.failedCount
            checkpoint.cursorOffset += batch.count
            checkpoint.lastAssetCreationDate = batch.last?.creationDate
            checkpoint.updatedAt = Date()
            try await checkpointRepository.save(checkpoint)
            onProgress(checkpoint)
        }

        checkpoint.status = checkpoint.failedCount > 0 ? .partiallyCompleted : .completed
        checkpoint.completedAt = Date()
        checkpoint.updatedAt = Date()
        try await checkpointRepository.save(checkpoint)
        onProgress(checkpoint)

        NiziLogger.discovery.info("scan_completed processed=\(checkpoint.processedCount, privacy: .public) failed=\(checkpoint.failedCount, privacy: .public)")
    }

    private func matchingCheckpoint(
        scopeKey: String, libraryVersion: String, total: Int
    ) async throws -> ScanCheckpoint? {
        if let exact = try await checkpointRepository.checkpoint(
            for: .initial, scopeKey: scopeKey, libraryVersion: libraryVersion,
            algorithmVersion: ScanCheckpoint.algorithmVersion
        ) {
            return exact
        }

        // One-time migration path from the original single checkpoint. It only applies to a
        // completed full-library scan whose processed count covers the current library, so a
        // historical scoped scan can never suppress a full scan.
        guard scopeKey == "full-library",
              let legacy = try await checkpointRepository.checkpoint(for: .initial, scopeKey: "legacy"),
              legacy.status == .completed || legacy.status == .partiallyCompleted,
              legacy.processedCount >= total
        else { return nil }

        var adopted = legacy
        adopted.scopeKey = scopeKey
        adopted.libraryVersion = libraryVersion
        adopted.algorithmVersion = ScanCheckpoint.algorithmVersion
        return adopted
    }

    private func libraryVersion(total: Int, dateRanges: [DateRangeFilter]) async throws -> String {
        guard total > 0 else { return "0" }
        let latest = try await assetProvider.fetchAssetRecords(
            offset: total - 1, limit: 1, dateRanges: dateRanges
        ).first
        let timestamp = latest?.creationDate?.timeIntervalSince1970 ?? -1
        return "\(total)#\(latest?.id ?? "missing")#\(timestamp)"
    }
}
