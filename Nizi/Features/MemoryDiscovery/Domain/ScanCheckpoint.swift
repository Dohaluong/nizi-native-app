//
//  ScanCheckpoint.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// See docs/database/memory-discovery.md § 5 (md_scan_checkpoint.scan_type).
/// Only `.initial` is driven by Sprint 3; the rest exist so the schema doesn't need to change later.
enum ScanType: String, Equatable {
    case initial
    case incremental
    case reanalyze
    case recluster
}

/// See docs/database/memory-discovery.md § 5 (md_scan_checkpoint.status).
enum ScanStatus: String, Equatable {
    case idle
    case running
    case paused
    case completed
    case partiallyCompleted
    case failed
    case cancelled
}

/// Resumable progress marker for a batch scan. Persisted so a scan can survive
/// pause, app relaunch, or termination mid-batch — see ADR-MD-009.
struct ScanCheckpoint: Equatable {
    var scanType: ScanType
    var status: ScanStatus
    var startedAt: Date
    var completedAt: Date?
    var totalAssetsEstimated: Int?
    var processedCount: Int
    var failedCount: Int
    /// Offset into the PhotoKit fetch result, ascending by `creationDate`. See
    /// docs/sprint/SPRINT-003-INTEGRATION-CHECKLIST.md for the tradeoffs of this over a stable cursor.
    var cursorOffset: Int
    var lastAssetCreationDate: Date?
    var errorMessage: String?
    var updatedAt: Date

    static func newInitial(now: Date = Date()) -> ScanCheckpoint {
        ScanCheckpoint(
            scanType: .initial,
            status: .idle,
            startedAt: now,
            completedAt: nil,
            totalAssetsEstimated: nil,
            processedCount: 0,
            failedCount: 0,
            cursorOffset: 0,
            lastAssetCreationDate: nil,
            errorMessage: nil,
            updatedAt: now
        )
    }
}
