//
//  MDScanCheckpoint.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import SwiftData

/// SwiftData schema v1 — see docs/database/memory-discovery.md § 5.
/// Scoped down from the doc: one row per `scanType` (unique), since Sprint 3 only
/// ever tracks a single running `.initial` scan — see docs/modules/memory-discovery/SPEC.md MVP scope.
@Model
final class MDScanCheckpoint {
    @Attribute(.unique) var scanType: String
    var status: String
    var startedAt: Date
    var completedAt: Date?
    var totalAssetsEstimated: Int?
    var processedCount: Int
    var failedCount: Int
    var cursorOffset: Int
    var lastAssetCreationDate: Date?
    var errorMessage: String?
    var updatedAt: Date

    init(checkpoint: ScanCheckpoint) {
        scanType = checkpoint.scanType.rawValue
        status = checkpoint.status.rawValue
        startedAt = checkpoint.startedAt
        completedAt = checkpoint.completedAt
        totalAssetsEstimated = checkpoint.totalAssetsEstimated
        processedCount = checkpoint.processedCount
        failedCount = checkpoint.failedCount
        cursorOffset = checkpoint.cursorOffset
        lastAssetCreationDate = checkpoint.lastAssetCreationDate
        errorMessage = checkpoint.errorMessage
        updatedAt = checkpoint.updatedAt
    }

    func apply(_ checkpoint: ScanCheckpoint) {
        status = checkpoint.status.rawValue
        completedAt = checkpoint.completedAt
        totalAssetsEstimated = checkpoint.totalAssetsEstimated
        processedCount = checkpoint.processedCount
        failedCount = checkpoint.failedCount
        cursorOffset = checkpoint.cursorOffset
        lastAssetCreationDate = checkpoint.lastAssetCreationDate
        errorMessage = checkpoint.errorMessage
        updatedAt = checkpoint.updatedAt
    }
}

extension ScanCheckpoint {
    init(model: MDScanCheckpoint) {
        self.init(
            scanType: ScanType(rawValue: model.scanType) ?? .initial,
            status: ScanStatus(rawValue: model.status) ?? .idle,
            startedAt: model.startedAt,
            completedAt: model.completedAt,
            totalAssetsEstimated: model.totalAssetsEstimated,
            processedCount: model.processedCount,
            failedCount: model.failedCount,
            cursorOffset: model.cursorOffset,
            lastAssetCreationDate: model.lastAssetCreationDate,
            errorMessage: model.errorMessage,
            updatedAt: model.updatedAt
        )
    }
}
