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
    /// Bumped whenever the scan interpretation changes. A completed checkpoint from an older
    /// scanner must never suppress a new scan.
    static let algorithmVersion = 2

    var scanType: ScanType
    /// Stable description of the requested range(s). `full-library` is intentionally different
    /// from every year/month selection.
    var scopeKey: String
    /// Snapshot of the PhotoKit result set at the moment this scan began.
    var libraryVersion: String
    var algorithmVersion: Int
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
            scopeKey: "full-library",
            libraryVersion: "unknown",
            algorithmVersion: Self.algorithmVersion,
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

    static func scopeKey(for dateRanges: [DateRangeFilter]) -> String {
        guard !dateRanges.isEmpty else { return "full-library" }
        return dateRanges
            .map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
    }

    var identityKey: String {
        "\(scanType.rawValue)#\(scopeKey)#\(libraryVersion)#\(algorithmVersion)"
    }
}
