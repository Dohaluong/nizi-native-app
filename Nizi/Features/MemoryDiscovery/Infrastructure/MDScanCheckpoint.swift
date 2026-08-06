//
//  MDScanCheckpoint.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import SwiftData

/// SwiftData schema v1 — see docs/database/memory-discovery.md § 5.
/// Checkpoints are scoped by scan request, Photo library snapshot and scanner algorithm. A
/// completed yearly scan therefore cannot suppress a later full-library scan.
@Model
final class MDScanCheckpoint {
    @Attribute(.unique) var identityKey: String
    var scanType: String
    var scopeKey: String
    var libraryVersion: String
    var algorithmVersion: Int
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
        identityKey = checkpoint.identityKey
        scanType = checkpoint.scanType.rawValue
        scopeKey = checkpoint.scopeKey
        libraryVersion = checkpoint.libraryVersion
        algorithmVersion = checkpoint.algorithmVersion
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
            scopeKey: model.scopeKey,
            libraryVersion: model.libraryVersion,
            algorithmVersion: model.algorithmVersion,
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
