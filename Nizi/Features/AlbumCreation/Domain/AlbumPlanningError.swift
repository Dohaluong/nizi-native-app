//
//  AlbumPlanningError.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Every way `AlbumDraftPlanning.createDraft(from:)` can fail. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 22.
enum AlbumPlanningError: Error, Equatable {
    case noEvents
    case noSelectedPhotos
    case invalidPhotoDimensions(photoId: String)
    case coverSelectionFailed
    case noValidSpreadPartition(photoCount: Int)
    case noCompatibleLayout(photoCount: Int)
    case slotAssignmentFailed(layoutId: String)
    case invalidDraft
    /// A Spread needs at least 2 photos (§ 2.3) — if the *entire* selection is a single photo,
    /// no Spread can ever be formed. Distinct from `noSelectedPhotos` (zero photos).
    case insufficientPhotos(minimum: Int, actual: Int)
}
