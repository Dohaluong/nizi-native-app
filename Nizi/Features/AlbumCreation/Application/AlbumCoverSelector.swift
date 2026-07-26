//
//  AlbumCoverSelector.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Picks the cover photo from an Album's full selected-photo set, using each photo's
/// already-computed `importance.totalScore` — this selector does *not* score photos itself
/// (docs/specs/SPEC-ALBUM-PLANNER.md § 6.4: "Không tính scoring lần thứ hai trong Cover
/// Selector"). Callers must run `PhotoImportanceEvaluating` over the photo set first.
protocol AlbumCoverSelecting {
    func selectCover(from photos: [AlbumPlanningPhoto]) throws -> AlbumPlanningPhoto
}

struct DefaultAlbumCoverSelector: AlbumCoverSelecting {
    /// § 6.4 tie breaker: highest importance → higher resolution → earlier creation date →
    /// lexical photo ID.
    func selectCover(from photos: [AlbumPlanningPhoto]) throws -> AlbumPlanningPhoto {
        guard !photos.isEmpty else { throw AlbumPlanningError.coverSelectionFailed }

        guard let winner = photos.sorted(by: { lhs, rhs in
            if lhs.importance.totalScore != rhs.importance.totalScore {
                return lhs.importance.totalScore > rhs.importance.totalScore
            }
            if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount > rhs.pixelCount }
            switch (lhs.creationDate, rhs.creationDate) {
            case let (l?, r?) where l != r: return l < r
            case (nil, .some): return false
            case (.some, nil): return true
            default: return lhs.id < rhs.id
            }
        }).first else {
            throw AlbumPlanningError.coverSelectionFailed
        }
        return winner
    }
}
