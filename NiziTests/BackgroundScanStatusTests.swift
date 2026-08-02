//
//  BackgroundScanStatusTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation
import Testing
@testable import Nizi

struct BackgroundScanStatusTests {
    private func makeCheckpoint(
        status: ScanStatus, totalAssetsEstimated: Int?, processedCount: Int
    ) -> ScanCheckpoint {
        ScanCheckpoint(
            scanType: .initial, status: status, startedAt: Date(), completedAt: nil,
            totalAssetsEstimated: totalAssetsEstimated, processedCount: processedCount, failedCount: 0,
            cursorOffset: processedCount, lastAssetCreationDate: nil, errorMessage: nil, updatedAt: Date()
        )
    }

    @Test func remainingCountIsZeroForNilCheckpoint() {
        #expect(BackgroundScanStatus.remainingCount(for: nil) == 0)
    }

    @Test func remainingCountIsZeroWhenTotalIsUnknown() {
        let checkpoint = makeCheckpoint(status: .running, totalAssetsEstimated: nil, processedCount: 10)
        #expect(BackgroundScanStatus.remainingCount(for: checkpoint) == 0)
    }

    @Test func remainingCountIsTheDifference() {
        let checkpoint = makeCheckpoint(status: .running, totalAssetsEstimated: 1000, processedCount: 400)
        #expect(BackgroundScanStatus.remainingCount(for: checkpoint) == 600)
    }

    @Test func remainingCountNeverGoesNegative() {
        let checkpoint = makeCheckpoint(status: .partiallyCompleted, totalAssetsEstimated: 100, processedCount: 130)
        #expect(BackgroundScanStatus.remainingCount(for: checkpoint) == 0)
    }

    @Test func completedStatusNeverHasIncompleteWorkRegardlessOfCounts() {
        let checkpoint = makeCheckpoint(status: .completed, totalAssetsEstimated: 1000, processedCount: 400)
        #expect(!BackgroundScanStatus.hasIncompleteWork(checkpoint: checkpoint))
    }

    @Test func runningOrPausedWithRemainingWorkIsIncomplete() {
        let running = makeCheckpoint(status: .running, totalAssetsEstimated: 1000, processedCount: 400)
        let paused = makeCheckpoint(status: .paused, totalAssetsEstimated: 1000, processedCount: 400)
        #expect(BackgroundScanStatus.hasIncompleteWork(checkpoint: running))
        #expect(BackgroundScanStatus.hasIncompleteWork(checkpoint: paused))
    }

    /// `.partiallyCompleted` means the cursor already reached the end (just with some failures
    /// along the way) — nothing left to resume, even though status isn't literally `.completed`.
    @Test func partiallyCompletedWithNoRemainingWorkIsNotIncomplete() {
        let checkpoint = makeCheckpoint(status: .partiallyCompleted, totalAssetsEstimated: 1000, processedCount: 1000)
        #expect(!BackgroundScanStatus.hasIncompleteWork(checkpoint: checkpoint))
    }

    @Test func nilCheckpointIsNotIncomplete() {
        #expect(!BackgroundScanStatus.hasIncompleteWork(checkpoint: nil))
    }
}
