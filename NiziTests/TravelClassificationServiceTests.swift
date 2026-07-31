//
//  TravelClassificationServiceTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import Testing
@testable import Nizi

private func makePlace(countryCode: String, displayName: String) -> PhotoPlace {
    PhotoPlace(
        coordinate: PhotoCoordinate(latitude: 0, longitude: 0)!,
        name: nil, subLocality: nil, locality: displayName,
        subAdministrativeArea: nil, administrativeArea: nil,
        country: displayName, isoCountryCode: countryCode, displayName: displayName
    )
}

private struct MockPhotoPlaceResolving: PhotoPlaceResolving {
    let resolve: @Sendable (PhotoCoordinate) async throws -> PhotoPlace
    func resolvePlace(for coordinate: PhotoCoordinate) async throws -> PhotoPlace {
        try await resolve(coordinate)
    }
}

private struct AlwaysThrowsResolver: PhotoPlaceResolving {
    func resolvePlace(for coordinate: PhotoCoordinate) async throws -> PhotoPlace {
        throw PhotoLocationError.geocodingFailed
    }
}

private actor MockPhotoPlaceCache: PhotoPlaceCaching {
    private var storage: [PhotoPlaceCacheKey: PhotoPlace] = [:]
    func place(for key: PhotoPlaceCacheKey) async -> PhotoPlace? { storage[key] }
    func store(_ place: PhotoPlace, for key: PhotoPlaceCacheKey) async { storage[key] = place }
}

struct TravelClassificationServiceTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!

    private func makeTrip(overnightCount: Int, primaryLatitude: Double?, primaryLongitude: Double?) -> PhotoTrip {
        PhotoTrip(
            id: UUID(), startDate: Self.reference,
            endDate: Self.reference.addingTimeInterval(86400 * Double(max(overnightCount, 1))),
            eventIDs: [UUID()], primaryLatitude: primaryLatitude, primaryLongitude: primaryLongitude,
            primaryCountryCode: nil, primaryPlaceName: nil, classification: .unknown, confidence: 0.8,
            travelContext: TravelContext(
                homeCountryCode: nil, maxDistanceFromHomeKm: 500, overnightCount: overnightCount,
                countryCodes: [], hasDepartureFromHome: true, hasReturnToHome: true
            )
        )
    }

    /// SPEC § 29 — a Day Trip never needs geocoding at all.
    @Test func zeroOvernightsClassifiesAsDayTripWithoutGeocoding() async {
        let service = TravelClassificationService(placeResolver: AlwaysThrowsResolver(), placeCache: MockPhotoPlaceCache())
        let home = HomeAnchor(clusterID: UUID(), centerLatitude: 21.0285, centerLongitude: 105.8542, homeScore: 0.9, confidence: .high)
        let trip = makeTrip(overnightCount: 0, primaryLatitude: 16.0544, primaryLongitude: 108.2022)

        let classified = await service.classify(trips: [trip], home: home)

        #expect(classified.first?.classification == .dayTrip)
    }

    @Test func sameCountryAsHomeClassifiesAsDomestic() async {
        let resolver = MockPhotoPlaceResolving { coordinate in
            coordinate.latitude > 30 ? makePlace(countryCode: "JP", displayName: "Tokyo") : makePlace(countryCode: "VN", displayName: "Da Nang")
        }
        let service = TravelClassificationService(placeResolver: resolver, placeCache: MockPhotoPlaceCache())
        let home = HomeAnchor(clusterID: UUID(), centerLatitude: 21.0285, centerLongitude: 105.8542, homeScore: 0.9, confidence: .high)
        let trip = makeTrip(overnightCount: 2, primaryLatitude: 16.0544, primaryLongitude: 108.2022)

        let classified = await service.classify(trips: [trip], home: home)

        #expect(classified.first?.classification == .domesticTrip)
    }

    @Test func differentCountryFromHomeClassifiesAsInternational() async {
        let resolver = MockPhotoPlaceResolving { coordinate in
            coordinate.latitude > 30 ? makePlace(countryCode: "JP", displayName: "Tokyo") : makePlace(countryCode: "VN", displayName: "Hanoi")
        }
        let service = TravelClassificationService(placeResolver: resolver, placeCache: MockPhotoPlaceCache())
        let home = HomeAnchor(clusterID: UUID(), centerLatitude: 21.0285, centerLongitude: 105.8542, homeScore: 0.9, confidence: .high)
        let trip = makeTrip(overnightCount: 4, primaryLatitude: 35.6762, primaryLongitude: 139.6503)

        let classified = await service.classify(trips: [trip], home: home)

        #expect(classified.first?.classification == .internationalTrip)
        #expect(classified.first?.primaryCountryCode == "JP")
    }

    @Test func geocodingFailureClassifiesAsUnknownWithoutCrashing() async {
        let service = TravelClassificationService(placeResolver: AlwaysThrowsResolver(), placeCache: MockPhotoPlaceCache())
        let home = HomeAnchor(clusterID: UUID(), centerLatitude: 21.0285, centerLongitude: 105.8542, homeScore: 0.9, confidence: .high)
        let trip = makeTrip(overnightCount: 3, primaryLatitude: 16.0544, primaryLongitude: 108.2022)

        let classified = await service.classify(trips: [trip], home: home)

        #expect(classified.first?.classification == .unknown)
    }
}
