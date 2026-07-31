//
//  PhotoTrip.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// A journey that may contain multiple `PhotoEvent`s — never used to represent a single
/// multi-day Event on its own (SPEC § 23/§ 24: "Không dùng PhotoEvent để đại diện cả chuyến du
/// lịch nhiều ngày"). `TripDiscoveryEngine` only ever groups `.away`-context events; classification
/// (country resolution) is filled in afterward by the Application-layer `TravelClassificationService`.
struct PhotoTrip: Identifiable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let eventIDs: [UUID]
    /// The farthest-from-home point in the trip — representative enough for country resolution
    /// even for a multi-city trip that never splits by city (SPEC § 31/§ 33).
    let primaryLatitude: Double?
    let primaryLongitude: Double?
    var primaryCountryCode: String?
    var primaryPlaceName: String?
    var classification: TravelClassification
    let confidence: Double
    var travelContext: TravelContext
}
