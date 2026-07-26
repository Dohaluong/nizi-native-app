//
//  LocalAssetRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

struct UpsertResult: Equatable {
    let succeededCount: Int
    let failedCount: Int
}

struct YearMonthCount: Identifiable, Equatable {
    var id: String { "\(year)-\(month)" }
    let year: Int
    let month: Int
    let count: Int
}

/// See docs/database/memory-discovery.md § 4 and docs/modules/memory-discovery/ARCHITECTURE.md § 6.4.
/// Never exposes the underlying storage (SwiftData today, possibly GRDB later — ADR is deliberately silent
/// on which, so this protocol must stay storage-agnostic).
protocol LocalAssetRepository {
    /// Upserts by `PhotoAssetRecord.id` (`PHAsset.localIdentifier`). A single bad record must not
    /// fail the whole batch — failures are counted, not thrown.
    @discardableResult
    func upsert(_ records: [PhotoAssetRecord]) async throws -> UpsertResult
    func yearMonthStatistics() async throws -> [YearMonthCount]
    func totalIndexedCount() async throws -> Int
    /// Available, indexed assets with a known creation date — the only ones eligible for clustering.
    func fetchClusterableAssets() async throws -> [IndexedAsset]
    /// Reads back specific assets by ID from the local index — never touches PhotoKit.
    /// IDs with no matching row are silently omitted (see docs/sprint/SPRINT-005B.md § 31).
    func fetchAssets(ids: [String]) async throws -> [IndexedAsset]
    func clearAll() async throws
}
