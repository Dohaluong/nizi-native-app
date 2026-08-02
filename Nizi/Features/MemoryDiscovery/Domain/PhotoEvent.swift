//
//  PhotoEvent.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// A proposed event, built from one or more merged `PhotoSession`s. Not an Album —
/// see ADR-MD-006. `sessionIDs`/`assetIDs` are materialized directly (see `PhotoSession`).
///
/// Deliberately drops the DB doc's separate `confidence` field for Sprint 4 — nothing yet
/// distinguishes it from `score` (that split matters once Vision-based signals arrive).
struct PhotoEvent: Identifiable, Equatable {
    let id: UUID
    var titleSuggestion: String
    let startDate: Date
    let endDate: Date
    /// Reverse geocoding is out of scope for Sprint 4 — see docs/sprint/SPRINT-004-INTEGRATION-CHECKLIST.md.
    var primaryLocationLabel: String?
    var eventPlace: EventPlace? = nil
    var placeResolutionState: EventPlaceResolutionState = .unresolved
    let eventType: EventType
    var score: Double
    var status: PhotoEventStatus
    /// A user-owned marker, persisted independently from discovery score/curation. A loved Event
    /// is surfaced in Home's "Kỷ niệm" section without creating a `MemoryCandidate`.
    var isLoved: Bool = false
    let sessionIDs: [UUID]
    let assetIDs: [String]
    var coverAssetID: String?
    var discoveryReasons: [DiscoveryReason]
    let algorithmVersion: Int
    let createdAt: Date
    var updatedAt: Date
    /// Set once by `FastEventQualityService` right after Event Discovery — a distinct concern
    /// from `score` above (which drives discovery confidence/sort order). See
    /// docs/sprint/SPRINT-FAST-EVENT-QUALITY.md § 2.
    var eventQualityScore: Double = 0
    var eventVisibility: EventVisibility = .normal
    /// Set once by `MemoryPotentialEvaluator` right after Trip classification — Nizi's own
    /// judgment that this Event is special enough to proactively surface as a "Kỷ niệm" on Home,
    /// independent of `isLoved`. See docs/sprint/SPRINT-NEXT.md § 10-14.
    var isAutoMemory: Bool = false
    var autoMemoryScore: Double = 0

    var assetCount: Int { assetIDs.count }
    var sessionCount: Int { sessionIDs.count }
}
