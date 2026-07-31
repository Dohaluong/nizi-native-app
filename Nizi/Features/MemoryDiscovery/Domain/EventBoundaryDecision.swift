//
//  EventBoundaryDecision.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

enum BoundaryAction: Equatable {
    case merge
    case split
}

/// One scored signal behind a boundary decision — shaped so a Diagnostics screen can render it
/// directly as a table row (name / detail / signed contribution), matching SPEC § 38's example
/// trace format.
struct BoundarySignalResult: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let detail: String
    let contribution: Double
}

/// Never just `Bool` — carries the full trace so Diagnostics can explain *why* (SPEC § 15/§ 41).
struct EventBoundaryDecision: Equatable {
    let action: BoundaryAction
    let score: Double
    let isHardBoundary: Bool
    let reasons: [BoundarySignalResult]
}

/// What `EventBoundaryEvaluating` needs beyond the two sessions themselves — Home/Familiar
/// context, and how long the event-in-progress has already run (SPEC § 22: merge threshold rises
/// with duration, in place of a separate `EventCohesion` score type).
struct EventBoundaryContext {
    let home: HomeAnchor?
    let familiarPlaces: [FamiliarPlace]
    let currentEventDurationHours: Double
    let currentEventSessionCount: Int
}
