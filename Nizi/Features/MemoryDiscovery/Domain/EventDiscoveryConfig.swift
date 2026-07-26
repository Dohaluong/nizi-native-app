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

    // Session → candidate merging (not separately threshold-specified in SPEC; chosen to mean
    // "an overnight gap, still roughly the same trip area")
    var sessionMergeMaxGapHours: Double = 24
    var sessionMergeMaxDistanceKm: Double = 100

    // Minimum event size (§10 "Minimum candidate")
    var minimumEventAssetCount: Int = 12
    var reducedMinimumEventAssetCount: Int = 6
    var highDensityAssetsPerHour: Double = 4

    // Reason generation
    var sameAreaCohesionThreshold: Double = 0.7

    // Noise scoring (§10 "Noise")
    var largeBurstFractionThreshold: Double = 0.5

    var algorithmVersion: Int = 1

    static let `default` = EventDiscoveryConfig()
}
