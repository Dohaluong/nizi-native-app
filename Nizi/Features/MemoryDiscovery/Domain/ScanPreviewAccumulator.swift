//
//  ScanPreviewAccumulator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Pure reducer — `previous` + one scan batch → next `ScanPreviewState`. Resets the candidate
/// buffer whenever the batch's year differs from `previous.currentYear` (a new year deserves its
/// own fresh representative photos, not stale carryover — SPRINT-INITIAL-SCAN-MEMORY-JOURNEY-HOME
/// § 6/§ 8), always keeps every favorite seen this year, and fills remaining buffer slots with the
/// most recently seen non-favorite, non-screenshot photos.
enum ScanPreviewAccumulator {
    static func reduce(previous: ScanPreviewState, batch: [PhotoAssetRecord], config: ScanPreviewConfig = .default) -> ScanPreviewState {
        let calendar = Calendar.current
        let latestDate = batch.compactMap(\.creationDate).max()
        let currentYear = latestDate.map { calendar.component(.year, from: $0) } ?? previous.currentYear

        var candidates: [ScanPreviewCandidate] = currentYear == previous.currentYear ? previous.candidates : []
        var seenIDs = Set(candidates.map(\.assetID))

        for record in batch where !record.isScreenshot && !record.isHidden && record.creationDate != nil {
            guard seenIDs.insert(record.id).inserted else { continue }
            candidates.append(ScanPreviewCandidate(assetID: record.id, isFavorite: record.isFavorite))
        }

        let favorites = candidates.filter(\.isFavorite)
        let others = candidates.filter { !$0.isFavorite }
        let keptOthers = Array(others.suffix(max(config.maxCandidates - favorites.count, 0)))

        return ScanPreviewState(currentYear: currentYear, candidates: favorites + keptOthers)
    }
}
