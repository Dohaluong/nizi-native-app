//
//  MDHomeAnchor.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import SwiftData

/// At most one meaningful row — `replaceLocationIntelligence` deletes and reinserts wholesale on
/// every rebuild, same idea as `MDMemoryCandidate`'s single-slot convention. Exception: a row
/// whose `source == .userConfirmed` is left untouched by that rebuild — see
/// `SwiftDataMemoryDiscoveryStore.replaceLocationIntelligence`/`confirmUserHome`.
@Model
final class MDHomeAnchor {
    @Attribute(.unique) var anchorID: UUID
    var clusterID: UUID
    var centerLatitude: Double
    var centerLongitude: Double
    var homeScore: Double
    var confidence: String
    /// Defaulted for lightweight migration — every row that existed before this sprint is,
    /// definitionally, an algorithmic guess.
    var source: String = HomeAnchorSource.inferred.rawValue
    var placeName: String?

    init(home: HomeAnchor) {
        anchorID = UUID()
        clusterID = home.clusterID
        centerLatitude = home.centerLatitude
        centerLongitude = home.centerLongitude
        homeScore = home.homeScore
        confidence = home.confidence.rawValue
        source = home.source.rawValue
        placeName = home.placeName
    }
}

extension HomeAnchor {
    init(model: MDHomeAnchor) {
        self.init(
            clusterID: model.clusterID,
            centerLatitude: model.centerLatitude,
            centerLongitude: model.centerLongitude,
            homeScore: model.homeScore,
            confidence: HomeConfidence(rawValue: model.confidence) ?? .low,
            source: HomeAnchorSource(rawValue: model.source) ?? .inferred,
            placeName: model.placeName
        )
    }
}
