//
//  MDPhotoTrip.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import SwiftData

/// `TravelContext`'s fields are flattened directly onto this model rather than stored as nested
/// Codable data — same convention `MDEventCandidate` uses for `DiscoveryReason`.
@Model
final class MDPhotoTrip {
    @Attribute(.unique) var tripID: UUID
    var startDate: Date
    var endDate: Date
    var eventIdentifiers: [UUID]
    var primaryLatitude: Double?
    var primaryLongitude: Double?
    var primaryCountryCode: String?
    var primaryPlaceName: String?
    var classification: String
    var confidence: Double

    var travelHomeCountryCode: String?
    var travelMaxDistanceFromHomeKm: Double?
    var travelOvernightCount: Int
    var travelCountryCodes: [String]
    var travelHasDepartureFromHome: Bool
    var travelHasReturnToHome: Bool

    init(trip: PhotoTrip) {
        tripID = trip.id
        startDate = trip.startDate
        endDate = trip.endDate
        eventIdentifiers = trip.eventIDs
        primaryLatitude = trip.primaryLatitude
        primaryLongitude = trip.primaryLongitude
        primaryCountryCode = trip.primaryCountryCode
        primaryPlaceName = trip.primaryPlaceName
        classification = trip.classification.rawValue
        confidence = trip.confidence

        travelHomeCountryCode = trip.travelContext.homeCountryCode
        travelMaxDistanceFromHomeKm = trip.travelContext.maxDistanceFromHomeKm
        travelOvernightCount = trip.travelContext.overnightCount
        travelCountryCodes = Array(trip.travelContext.countryCodes)
        travelHasDepartureFromHome = trip.travelContext.hasDepartureFromHome
        travelHasReturnToHome = trip.travelContext.hasReturnToHome
    }
}

extension PhotoTrip {
    init(model: MDPhotoTrip) {
        let travelContext = TravelContext(
            homeCountryCode: model.travelHomeCountryCode,
            maxDistanceFromHomeKm: model.travelMaxDistanceFromHomeKm,
            overnightCount: model.travelOvernightCount,
            countryCodes: Set(model.travelCountryCodes),
            hasDepartureFromHome: model.travelHasDepartureFromHome,
            hasReturnToHome: model.travelHasReturnToHome
        )
        self.init(
            id: model.tripID,
            startDate: model.startDate,
            endDate: model.endDate,
            eventIDs: model.eventIdentifiers,
            primaryLatitude: model.primaryLatitude,
            primaryLongitude: model.primaryLongitude,
            primaryCountryCode: model.primaryCountryCode,
            primaryPlaceName: model.primaryPlaceName,
            classification: TravelClassification(rawValue: model.classification) ?? .unknown,
            confidence: model.confidence,
            travelContext: travelContext
        )
    }
}
