//
//  EventCurationResult.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// The saved outcome of Photo Curation for one Event — see docs/sprint/SPRINT-005B.md § 16.1.
/// Not an Album; Sprint 006 (Album Draft) consumes this. See § 35 for the exact hand-off shape.
/// One-to-one with its event, so `id` is just `photoEventID` — no separate identity.
struct EventCurationResult: Identifiable, Equatable {
    let photoEventID: UUID
    var status: CurationStatus
    let algorithmVersion: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var sourceAssetCount: Int
    /// Order-independent digest of the Event's asset membership at curation time — the real cache
    /// identity (§ 9-11 of SPRINT-SMART-EVENT-HIGHLIGHTS.md). `sourceAssetCount` alone missed
    /// "same count, different assets" (one photo swapped for another); kept around for
    /// diagnostics/display, but no longer the sole signal cache validity checks.
    var sourceAssetFingerprint: String = ""
    var errorMessage: String?
    var groups: [PhotoCurationGroup]

    var id: UUID { photoEventID }
    var selectedAssetCount: Int { groups.flatMap(\.items).filter(\.isSelected).count }
    var groupCount: Int { groups.count }

    /// § 35 hand-off shape for Sprint 006, in display order.
    var orderedSelectedAssetIdentifiers: [String] {
        groups
            .sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { group in group.items.sorted { $0.sortOrder < $1.sortOrder } }
            .filter(\.isSelected)
            .map(\.assetID)
    }
}
