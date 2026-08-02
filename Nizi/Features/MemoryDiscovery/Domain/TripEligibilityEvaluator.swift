//
//  TripEligibilityEvaluator.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

/// A candidate maximal run of consecutive `.away`-context `PhotoEvent`s, before it's decided
/// whether that run is substantial enough to become a real `PhotoTrip` — see SPRINT-NEXT § 5-9.
struct TripCandidate {
    let events: [PhotoEvent]
    let overnightCount: Int
    let maxDistanceFromHomeKm: Double?
    let totalSessionCount: Int
    let durationHours: Double
}

enum TripEligibilityReason: String {
    case overnight
    case dayTrip
    case internationalCandidate
}

struct TripEligibilityDecision: Equatable {
    let isEligible: Bool
    let reasons: [String]
}

/// Separated from `TripDetecting`'s mechanical grouping the same way `EventBoundaryEvaluating` is
/// separated from `EventDiscoveryEngine`'s session grouping — mechanical "is this a maximal away
/// run" stays mechanical, "is this run substantial enough to be a Trip" is its own testable policy.
protocol TripEligibilityEvaluating {
    func evaluate(candidate: TripCandidate, config: EventDiscoveryConfig) -> TripEligibilityDecision
}

/// Trip Eligibility V1 (SPRINT-NEXT § 7): a candidate clears the gate if it satisfies at least one
/// of three independent rules. International Trip eligibility is deliberately coarse (distance
/// only) since the real country isn't known until `TravelClassificationService` reverse-geocodes
/// afterward — this only marks the candidate as *plausibly* international so it isn't dropped
/// before that async pass gets a chance to confirm or downgrade it.
struct DefaultTripEligibilityEvaluator: TripEligibilityEvaluating {
    func evaluate(candidate: TripCandidate, config: EventDiscoveryConfig) -> TripEligibilityDecision {
        var reasons: [TripEligibilityReason] = []

        if candidate.overnightCount >= 1,
           let distance = candidate.maxDistanceFromHomeKm, distance >= config.overnightTripMinimumDistanceKm {
            reasons.append(.overnight)
        }

        if candidate.durationHours >= config.dayTripMinimumDurationHours,
           let distance = candidate.maxDistanceFromHomeKm, distance >= config.dayTripMinimumDistanceKm,
           candidate.totalSessionCount >= config.dayTripMinimumSessionCount {
            reasons.append(.dayTrip)
        }

        if let distance = candidate.maxDistanceFromHomeKm, distance >= config.internationalTripCandidateMinimumDistanceKm {
            reasons.append(.internationalCandidate)
        }

        return TripEligibilityDecision(isEligible: !reasons.isEmpty, reasons: reasons.map(\.rawValue))
    }
}
