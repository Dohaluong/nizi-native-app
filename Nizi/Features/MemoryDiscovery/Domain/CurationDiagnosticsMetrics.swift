//
//  CurationDiagnosticsMetrics.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Per-Event curation metrics for Curation Diagnostics and logging — see
/// docs/sprint/SPRINT-SMART-EVENT-HIGHLIGHTS.md § 60. Pure, derived entirely from an already
/// -saved `EventCurationResult`; no Vision, no persistence.
struct CurationDiagnosticsMetrics: Equatable {
    let sourcePhotoCount: Int
    let usablePhotoCount: Int
    let localClusterCount: Int
    let localSelectedCount: Int
    let globalDuplicateSuppressedCount: Int
    let finalSelectedCount: Int
    let favoriteSourceCount: Int
    let favoriteSelectedCount: Int
    let userOverrideCount: Int

    static func compute(result: EventCurationResult, isFavoriteByAssetID: [String: Bool]) -> CurationDiagnosticsMetrics {
        let items = result.groups.flatMap(\.items)
        let usable = items.filter { item in
            item.rejectionReason != .screenshot && item.rejectionReason != .document && item.rejectionReason != .lowQuality
        }
        // "Locally selected" = survived local clustering/quality-gate, i.e. never selected then
        // later cut by global dedup or the event-wide trim, or still selected now.
        let locallySelected = items.filter { $0.isSelected || $0.rejectionReason == .globalDuplicate || $0.rejectionReason == .trimmed }

        return CurationDiagnosticsMetrics(
            sourcePhotoCount: items.count,
            usablePhotoCount: usable.count,
            localClusterCount: Set(items.map(\.similarityClusterID)).count,
            localSelectedCount: locallySelected.count,
            globalDuplicateSuppressedCount: items.filter { $0.rejectionReason == .globalDuplicate }.count,
            finalSelectedCount: items.filter(\.isSelected).count,
            favoriteSourceCount: items.filter { isFavoriteByAssetID[$0.assetID] == true }.count,
            favoriteSelectedCount: items.filter { $0.isSelected && isFavoriteByAssetID[$0.assetID] == true }.count,
            userOverrideCount: items.filter { $0.selectionSource != .systemSuggested }.count
        )
    }
}
