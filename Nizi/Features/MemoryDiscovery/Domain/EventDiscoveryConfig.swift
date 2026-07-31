//
//  EventDiscoveryConfig.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Every threshold `EventDiscoveryEngine` uses, in one place so nothing is hard-coded
/// inline — see docs/modules/memory-discovery/SPEC.md § 10 ("Không hard-code trong UI.
/// Đặt trong config."). Defaults come straight from that section; SPEC explicitly calls
/// the scoring weights "chỉ là điểm khởi đầu" (a starting point to tune against real data).
struct EventDiscoveryConfig: Equatable {
    // Temporal segmentation (§10 "Temporal rules")
    var tightGapMinutes: Double = 30
    var moderateGapHours: Double = 3
    var looseGapHours: Double = 8

    // Spatial rules (§10 "Spatial rules") — reused as the "location support" distance
    // for the 3–8h ambiguous gap bucket, and as the spatial-cohesion reference distance.
    var moderateGapLocationSupportKm: Double = 20

    // Minimum event size (§10 "Minimum candidate")
    var minimumEventAssetCount: Int = 12
    var reducedMinimumEventAssetCount: Int = 6
    var highDensityAssetsPerHour: Double = 4

    // Reason generation
    var sameAreaCohesionThreshold: Double = 0.7

    // Noise scoring (§10 "Noise")
    var largeBurstFractionThreshold: Double = 0.5

    // Location clustering (SPRINT-SMART-EVENT-TRAVEL-DISCOVERY § 7) — library-wide, for Home/
    // Familiar Place detection. Distinct from the per-session/per-event spatial rules above.
    var locationClusterRadiusMeters: Double = 500

    // Home detection (§ 8-11) — gated on distinct *days*, never asset count (§9's explicit
    // warning: a photo-heavy vacation must never outscore a lightly-photographed long-term home).
    var minimumHomeDistinctDays: Int = 5
    var minimumFamiliarDistinctDays: Int = 3
    var homeConfidenceThreshold: Double = 0.75
    var homeConfidenceMediumThreshold: Double = 0.55
    var homeConfidenceLowThreshold: Double = 0.35

    // LocationContext (§ 13)
    var localRadiusKm: Double = 20
    var familiarPlaceRadiusMeters: Double = 500

    // Event Boundary Evaluator (§ 14-22). `eventDurationThresholdPenaltyPerDay` is how the merge
    // bar rises the longer an event has already run, in place of a separate `EventCohesion` score
    // (§21/§22 — "merge threshold increases with event duration").
    var eventBoundaryMergeThreshold: Double = 0.35
    var eventDurationThresholdPenaltyPerDay: Double = 0.05
    var hardBoundaryTimeGapHours: Double = 16
    var hardBoundaryDistanceKm: Double = 100

    // Trip Discovery (§ 25/§ 34)
    var minimumTripTerminationGapHours: Double = 72

    var algorithmVersion: Int = 1

    static let `default` = EventDiscoveryConfig()
}
