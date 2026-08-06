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

    // Trip Eligibility V1 (SPRINT-NEXT § 5-9) — a maximal away-context run only becomes a real
    // PhotoTrip when it clears at least one of these three gates. `overnightTripMinimumDistanceKm`
    // is deliberately only just above `localRadiusKm`(20) as an explicit, independently-tunable
    // floor — grouping already only admits `.away` (>20km) events, so this isn't a duplicate gate,
    // just a clearly-named one. The Day Trip gate (duration+distance+session count together) is
    // what actually stops a single short, nearby-ish event from becoming a Trip.
    var overnightTripMinimumDistanceKm: Double = 25
    var dayTripMinimumDurationHours: Double = 4
    var dayTripMinimumDistanceKm: Double = 30
    var dayTripMinimumSessionCount: Int = 2
    // Coarse "plausibly abroad" floor — the real country is confirmed or downgraded afterward by
    // `TravelClassificationService`'s reverse-geocoding; this only keeps a candidate from being
    // dropped before that async pass gets a chance to look.
    var internationalTripCandidateMinimumDistanceKm: Double = 150
    /// Candidate-based discovery deliberately accepts low-confidence, evidence-backed journeys
    /// for diagnostics and later country verification instead of requiring every old hard gate.
    var tripCandidateMinimumConfidence: Double = 0.40

    // Fast Event Quality (SPRINT-FAST-EVENT-QUALITY § 10-14) — weighted scoring, no single
    // hard-reject rule. Every value here is a starting point pending real-library tuning.
    var eventQualityBaseScore: Double = 0.5
    var eventQualityLowAssetCountThreshold: Int = 5
    var eventQualityLowAssetCountPenalty: Double = 0.08
    var eventQualityFavoriteBonus: Double = 0.20
    var eventQualityShortDurationHoursThreshold: Double = 1.0
    var eventQualityShortDurationPenalty: Double = 0.08
    var eventQualityMomentGapSeconds: Double = 300
    var eventQualitySingleMomentPenalty: Double = 0.08
    var eventQualityManyMomentsThreshold: Int = 4
    var eventQualityManyMomentsBonus: Double = 0.10
    var eventQualityManySessionsThreshold: Int = 3
    var eventQualitySessionDiversityBonus: Double = 0.08
    var eventQualityScreenshotRatioThreshold: Double = 0.6
    var eventQualityScreenshotPenalty: Double = 0.30
    var eventQualityGPSBonus: Double = 0.05
    var eventQualityTripMembershipBonus: Double = 0.12
    var eventQualityMultiDayTripOvernightThreshold: Int = 1
    var eventQualityMultiDayTripBonus: Double = 0.08
    var eventQualityHomeContextPenalty: Double = 0.10
    var eventQualityNormalThreshold: Double = 0.55
    var eventQualityLowValueThreshold: Double = 0.30

    // Memory Potential V1 (SPRINT-NEXT § 10-14) — conservative by design: base gate + at least one
    // strong signal. `memoryPotentialQualityThreshold` sits meaningfully above
    // `eventQualityNormalThreshold`(0.55) so most merely-visible Events never qualify — the goal
    // is a small number of standout Auto Memories out of a full library, not most Events.
    var memoryPotentialQualityThreshold: Double = 0.65
    var memoryPotentialMultiDayTripOvernightThreshold: Int = 2
    var memoryPotentialLongDurationHours: Double = 6.0
    var memoryPotentialMinimumFavoriteCount: Int = 5
    var memoryPotentialMinimumFavoriteRatio: Double = 0.2
    var memoryPotentialMinimumSessionDiversity: Int = 3
    var memoryPotentialMinimumAssetCountForSignal: Int = 60

    var algorithmVersion: Int = 1

    static let `default` = EventDiscoveryConfig()
}
