//
//  MemoryBuilder.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Turns an eligible `PhotoEvent` + its `EventCurationResult` into a `MemoryCandidate` — the
/// "selected photos → cover selection → MemoryCandidate" tail of docs/sprint/
/// SPRINT-FIRST-MEMORY-EXPERIENCE.md § 8. Pure, no I/O.
struct MemoryBuilder {
    func build(event: PhotoEvent, curation: EventCurationResult, score: Double) -> MemoryCandidate? {
        let selected = curation.orderedSelectedAssetIdentifiers
        guard !selected.isEmpty else { return nil }

        let now = Date()
        return MemoryCandidate(
            id: UUID(),
            eventID: event.id,
            title: event.primaryLocationLabel ?? event.eventType.displayLabel,
            subtitle: nil,
            startDate: event.startDate,
            endDate: event.endDate,
            placeName: event.primaryLocationLabel,
            coverAssetID: bestCoverAssetID(curation: curation) ?? event.coverAssetID ?? selected[0],
            selectedAssetIDs: selected,
            totalPhotoCount: selected.count,
            score: score,
            status: .ready,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Used only when curation itself failed (§ 24 "Curation failure... fallback chọn cover +
    /// một tập ảnh đơn giản nếu an toàn") — a simple, safe selection straight from the event's
    /// own asset list (already creation-date ascending, see `fetchClusterableAssets`), favorites
    /// first when there's a way to tell, capped at 12 so the fallback Memory Viewer never blows up.
    func buildFallback(event: PhotoEvent) -> MemoryCandidate? {
        guard !event.assetIDs.isEmpty else { return nil }
        let selected = Array(event.assetIDs.prefix(12))
        let now = Date()
        return MemoryCandidate(
            id: UUID(),
            eventID: event.id,
            title: event.primaryLocationLabel ?? event.eventType.displayLabel,
            subtitle: nil,
            startDate: event.startDate,
            endDate: event.endDate,
            placeName: event.primaryLocationLabel,
            coverAssetID: event.coverAssetID ?? selected[0],
            selectedAssetIDs: selected,
            totalPhotoCount: selected.count,
            score: 0,
            status: .ready,
            createdAt: now,
            updatedAt: now
        )
    }

    /// The selected item with the highest Vision quality score (`PhotoCurationItem.qualityScore`,
    /// 0...100) makes a better cover than the discovery engine's cheaper `pickCoverAssetID`
    /// heuristic (`EventDiscoveryEngine.pickCoverAssetID`), which only avoids screenshots.
    private func bestCoverAssetID(curation: EventCurationResult) -> String? {
        curation.groups
            .flatMap(\.items)
            .filter(\.isSelected)
            .max(by: { $0.qualityScore < $1.qualityScore })?
            .assetID
    }
}
