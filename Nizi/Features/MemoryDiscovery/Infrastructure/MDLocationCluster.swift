//
//  MDLocationCluster.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import SwiftData

/// SwiftData schema for `LocationCluster` — flat/materialized fields, same convention as
/// `MDEventCandidate`. Wholesale-replaced on every rebuild (see `LocationIntelligenceRepository`).
@Model
final class MDLocationCluster {
    @Attribute(.unique) var clusterID: UUID
    var centerLatitude: Double
    var centerLongitude: Double
    var radiusMeters: Double
    var assetIdentifiers: [String]
    var distinctDayCount: Int
    var distinctMonthCount: Int
    var visitRunCount: Int
    var firstSeenAt: Date
    var lastSeenAt: Date
    var eveningOrNightAssetRatio: Double

    init(cluster: LocationCluster) {
        clusterID = cluster.id
        centerLatitude = cluster.centerLatitude
        centerLongitude = cluster.centerLongitude
        radiusMeters = cluster.radiusMeters
        assetIdentifiers = cluster.assetIDs
        distinctDayCount = cluster.distinctDayCount
        distinctMonthCount = cluster.distinctMonthCount
        visitRunCount = cluster.visitRunCount
        firstSeenAt = cluster.firstSeenAt
        lastSeenAt = cluster.lastSeenAt
        eveningOrNightAssetRatio = cluster.eveningOrNightAssetRatio
    }
}

extension LocationCluster {
    init(model: MDLocationCluster) {
        self.init(
            id: model.clusterID,
            centerLatitude: model.centerLatitude,
            centerLongitude: model.centerLongitude,
            radiusMeters: model.radiusMeters,
            assetIDs: model.assetIdentifiers,
            distinctDayCount: model.distinctDayCount,
            distinctMonthCount: model.distinctMonthCount,
            visitRunCount: model.visitRunCount,
            firstSeenAt: model.firstSeenAt,
            lastSeenAt: model.lastSeenAt,
            eveningOrNightAssetRatio: model.eveningOrNightAssetRatio
        )
    }
}
