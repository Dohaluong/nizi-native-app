//
//  AlbumLayoutPlanningContext.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Recent layout-pair history `AlbumLayoutPairSelector` uses to prefer variety among
/// near-equivalent candidates — never persisted as part of `AlbumDraft` (docs/specs/
/// SPEC-ALBUM-PLANNER.md § 9: "Không cần lưu vào domain Album nếu chỉ dùng trong quá trình
/// plan"), purely an in-memory planning aid threaded from one Spread's selection to the next.
struct AlbumLayoutPlanningContext {
    var previousLeftLayoutId: String?
    var previousRightLayoutId: String?
    var previousPartition: AlbumPagePartition?
    /// Up to the last 2 Spreads' partitions, oldest first — lets the selector notice a pattern
    /// that's stale across a short window, not just an exact repeat of the immediately-previous
    /// Spread (docs/specs/SPEC-MODIFY-DRAFT.md § 8/§ 9).
    var recentPartitions: [AlbumPagePartition] = []
    /// Individual page layout IDs from the last 2–3 Pages, most recent last (§ 9: "layout xuất
    /// hiện trong 2–3 Page gần nhất").
    var recentlyUsedLayoutIds: [String] = []

    static let empty = AlbumLayoutPlanningContext()

    /// Rolls this context forward after a Spread's layout pair has been chosen.
    func advanced(leftLayoutId: String, rightLayoutId: String, partition: AlbumPagePartition) -> AlbumLayoutPlanningContext {
        var next = self
        next.previousLeftLayoutId = leftLayoutId
        next.previousRightLayoutId = rightLayoutId
        next.previousPartition = partition
        next.recentPartitions = (recentPartitions + [partition]).suffix(2).map { $0 }
        next.recentlyUsedLayoutIds = (recentlyUsedLayoutIds + [leftLayoutId, rightLayoutId]).suffix(4).map { $0 }
        return next
    }
}
