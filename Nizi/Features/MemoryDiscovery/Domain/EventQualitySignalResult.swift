//
//  EventQualitySignalResult.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

/// One scored signal behind a Fast Event Quality decision — same shape as
/// `BoundarySignalResult` (`EventBoundaryDecision.swift`) so a Diagnostics screen can render it
/// the same way (name / detail / signed contribution). See
/// docs/sprint/SPRINT-FAST-EVENT-QUALITY.md § 16-17 — explainability is a requirement, not just
/// a bare score.
struct EventQualitySignalResult: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let detail: String
    let contribution: Double
}

/// The full trace behind one Event's `eventQualityScore`/`eventVisibility` — Diagnostics-only,
/// never persisted (only the two final fields are, on `PhotoEvent`/`MDEventCandidate`).
struct EventQualityTrace: Equatable {
    let eventID: UUID
    let score: Double
    let visibility: EventVisibility
    let reasons: [EventQualitySignalResult]
}
