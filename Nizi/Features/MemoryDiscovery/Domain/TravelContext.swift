//
//  TravelContext.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// The evidence `TravelClassificationService` needs to label a `PhotoTrip` — country resolution
/// itself happens at the Application layer (needs reverse-geocoding); this struct only carries
/// what pure `TripDiscoveryEngine` can already compute plus a slot for the resolved country codes
/// to be filled in afterward.
struct TravelContext: Equatable {
    var homeCountryCode: String?
    var maxDistanceFromHomeKm: Double?
    var overnightCount: Int
    var countryCodes: Set<String>
    var hasDepartureFromHome: Bool
    var hasReturnToHome: Bool
}
