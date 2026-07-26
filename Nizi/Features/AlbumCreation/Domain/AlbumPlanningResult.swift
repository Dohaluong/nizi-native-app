//
//  AlbumPlanningResult.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// `AlbumDraftPlanning.createDraft(from:)`'s return value — the Draft plus the structured log of
/// how the planner arrived at it. See docs/specs/SPEC-ALBUM-PLANNER.md § 7.4.
struct AlbumPlanningResult {
    let draft: AlbumDraft
    let log: AlbumPlanningLog
}
