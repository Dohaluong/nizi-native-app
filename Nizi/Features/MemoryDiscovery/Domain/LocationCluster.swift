//
//  LocationCluster.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// A library-wide recurring-location cluster — the substrate `LocationIntelligenceEngine` scores
/// for Home/Familiar Place detection. Deliberately distinct from `PhotoLocation`'s
/// `PhotoLocationCluster` (which only groups photos for one reverse-geocode call, within a single
/// Album-planning pass) — this tracks the temporal-recurrence signals Home detection needs
/// (`distinctDayCount`, `visitRunCount`, span) that the other type never computes. See
/// docs/sprint/SPRINT-SMART-EVENT-TRAVEL-DISCOVERY.md § 7.
///
/// Plain `Double` lat/lon, not `CLLocationCoordinate2D` — this module's Domain layer never
/// imports CoreLocation (see `EventDiscoveryEngine`'s own hand-rolled haversine).
struct LocationCluster: Identifiable, Equatable {
    let id: UUID
    let centerLatitude: Double
    let centerLongitude: Double
    let radiusMeters: Double
    let assetIDs: [String]
    let distinctDayCount: Int
    let distinctMonthCount: Int
    /// Separate visits to this place, where a gap of more than one calendar day between visits
    /// starts a new run — five consecutive daily photos count as one run, not five. The Home-score
    /// "return frequency" signal (SPEC § 9) is this, not raw `distinctDayCount`.
    let visitRunCount: Int
    let firstSeenAt: Date
    let lastSeenAt: Date
    /// Fraction of member assets taken in the evening/night local-hour window — computed once
    /// while building the cluster (already iterating every member asset), not re-derived later.
    let eveningOrNightAssetRatio: Double

    var assetCount: Int { assetIDs.count }
}
