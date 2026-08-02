//
//  TravelClassification+DisplayLabel.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

extension TravelClassification {
    /// Every case gets a label — `.local`/`.dayTrip`/`.unknown` have no dedicated filter chip on
    /// Trips List but can still appear under "All", and must never fall back to printing the raw
    /// enum case name (matches `EventType.displayLabel`'s convention).
    var displayLabel: String {
        switch self {
        case .local: localizedString("trip.classification.local", defaultValue: "Nearby")
        case .dayTrip: localizedString("trip.classification.day_trip", defaultValue: "Day Trip")
        case .domesticTrip: localizedString("trip.classification.domestic", defaultValue: "Domestic")
        case .internationalTrip: localizedString("trip.classification.international", defaultValue: "International")
        case .unknown: localizedString("trip.classification.unknown", defaultValue: "Trip")
        }
    }
}
