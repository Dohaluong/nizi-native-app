//
//  BackgroundScanStatus.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

/// Pure derivation from a `ScanCheckpoint` — kept separate from `BackgroundScanCoordinator`
/// (which owns the actual async scan/discover Tasks) so this decision logic is unit-testable
/// without any `ModelContainer`/actor setup, same idiom as `ScanPreviewAccumulator`.
enum BackgroundScanStatus {
    static func remainingCount(for checkpoint: ScanCheckpoint?) -> Int {
        guard let checkpoint, let total = checkpoint.totalAssetsEstimated else { return 0 }
        return max(total - checkpoint.processedCount, 0)
    }

    /// Drives Home's "still surveying" nudge card — true only while there's real work left and
    /// the scan hasn't already reached `.completed` (a `.partiallyCompleted` scan whose cursor
    /// already reached the end has nothing left to resume, even though its status isn't literally
    /// `.completed`).
    static func hasIncompleteWork(checkpoint: ScanCheckpoint?) -> Bool {
        guard let checkpoint else { return false }
        return checkpoint.status != .completed && remainingCount(for: checkpoint) > 0
    }
}
