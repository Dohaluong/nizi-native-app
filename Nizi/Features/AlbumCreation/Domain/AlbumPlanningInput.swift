//
//  AlbumPlanningInput.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// One Event's worth of already-user-selected photos — the planner never re-selects or discovers
/// photos of its own; it only works with what's here. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 5.
struct AlbumPlanningEvent: Identifiable, Hashable {
    let id: String
    let title: String?
    let startDate: Date?
    let endDate: Date?
    let locationName: String?
    let latitude: Double?
    let longitude: Double?
    let selectedPhotos: [AlbumPlanningPhoto]
}

struct AlbumPlanningInput: Hashable {
    let albumTitle: String?
    let events: [AlbumPlanningEvent]
}
