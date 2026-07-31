//
//  MDFamiliarPlace.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import SwiftData

@Model
final class MDFamiliarPlace {
    @Attribute(.unique) var placeID: UUID
    var clusterID: UUID
    var centerLatitude: Double
    var centerLongitude: Double
    var confidence: Double

    init(place: FamiliarPlace) {
        placeID = place.id
        clusterID = place.clusterID
        centerLatitude = place.centerLatitude
        centerLongitude = place.centerLongitude
        confidence = place.confidence
    }
}

extension FamiliarPlace {
    init(model: MDFamiliarPlace) {
        self.init(
            id: model.placeID,
            clusterID: model.clusterID,
            centerLatitude: model.centerLatitude,
            centerLongitude: model.centerLongitude,
            confidence: model.confidence
        )
    }
}
