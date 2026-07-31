//
//  HomeAnchor.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// How sure `LocationIntelligenceEngine` is that a `HomeAnchor` is real — bucketed from
/// `homeScore` against `EventDiscoveryConfig`'s three threshold fields. A cluster whose score
/// doesn't clear even `.low` never becomes a `HomeAnchor` at all (see SPEC § 10: "Không gán Home
/// nếu confidence thấp" — the engine keeps working with `home == nil`).
enum HomeConfidence: String, Equatable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    static func < (lhs: HomeConfidence, rhs: HomeConfidence) -> Bool { lhs.rank < rhs.rank }
}

/// The dominant place a user is inferred to live — deliberately not a precise address (SPEC § 8:
/// "Không cần biết địa chỉ nhà chính xác"), just the coordinate of the winning `LocationCluster`.
/// Sprint V1 only tracks one (`dominantHomeAnchor` — SPEC § 11); nothing here prevents a future
/// Secondary Home/Work concept from being added as another `HomeAnchor` later.
///
/// `source`/`placeName` added by SPRINT-INITIAL-SCAN-MEMORY-JOURNEY-HOME — a `.userConfirmed`
/// anchor always wins over a freshly-computed `.inferred` one (see
/// `SwiftDataMemoryDiscoveryStore.replaceLocationIntelligence`), so the Full Home Detector's
/// periodic rebuilds can never silently overwrite a choice the user actually made.
struct HomeAnchor: Equatable {
    let clusterID: UUID
    let centerLatitude: Double
    let centerLongitude: Double
    let homeScore: Double
    let confidence: HomeConfidence
    var source: HomeAnchorSource = .inferred
    var placeName: String? = nil
}
