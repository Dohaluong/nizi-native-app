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
        onProgress: @escaping (ScanCheckpoint) -> Void
    ) async throws {
        var checkpoint = try await checkpointRepository.checkpoint(for: .initial) ?? .newInitial()

        if checkpoint.status == .completed {
            onProgress(checkpoint)
            return
        }

        let total = try await assetProvider.totalAssetCount(dateRanges: dateRanges)
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
}
