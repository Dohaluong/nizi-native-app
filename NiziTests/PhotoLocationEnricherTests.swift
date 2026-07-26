//
//  PhotoLocationEnricherTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// Counts calls and lets a test force success/failure — never touches `CLGeocoder`.
private actor MockPlaceResolver: PhotoPlaceResolving {
    private(set) var callCount = 0
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func resolvePlace(for coordinate: PhotoCoordinate) async throws -> PhotoPlace {
        callCount += 1
        if shouldFail { throw PhotoLocationError.geocodingFailed }
        return PhotoPlace(
            coordinate: coordinate, name: "Mock Place", subLocality: nil, locality: "Mock City",
            subAdministrativeArea: nil, administrativeArea: nil, country: "Mockland", isoCountryCode: "MK",
            displayName: "Mock Place, Mock City"
        )
    }
}

struct PhotoLocationEnricherTests {
    private func photo(id: String, coordinate: PhotoCoordinate?) -> AlbumPlanningPhoto {
        AlbumPlanningPhoto(
            id: id, eventId: "e", creationDate: nil, pixelWidth: 1600, pixelHeight: 1200,
            coordinate: coordinate, place: nil, isFavorite: false, isEdited: false,
            burstIdentifier: nil, originalFilename: nil, exif: nil
        )
    }

    private let coordinateA = PhotoCoordinate(latitude: -33.8568, longitude: 151.2153)!
    private let coordinateAClose = PhotoCoordinate(latitude: -33.8569, longitude: 151.2154)!

    @Test func oneClusterCallsResolverExactlyOnce() async {
        let resolver = MockPlaceResolver()
        let enricher = DefaultPhotoLocationEnricher(resolver: resolver)
        let photos = [photo(id: "a1", coordinate: coordinateA), photo(id: "a2", coordinate: coordinateAClose)]

        _ = await enricher.enrich(photos: photos)
        let calls = await resolver.callCount
        #expect(calls == 1)
    }

    @Test func cacheHitAvoidsASecondResolverCall() async {
        let resolver = MockPlaceResolver()
        let cache = InMemoryPhotoPlaceCache()
        let enricher = DefaultPhotoLocationEnricher(resolver: resolver, cache: cache)
        let photos = [photo(id: "a1", coordinate: coordinateA)]

        _ = await enricher.enrich(photos: photos)
        _ = await enricher.enrich(photos: photos) // same coordinate again, fresh enricher call
        let calls = await resolver.callCount
        #expect(calls == 1)
    }

    @Test func resolverFailureDoesNotBreakTheWholeResult() async {
        let resolver = MockPlaceResolver(shouldFail: true)
        let enricher = DefaultPhotoLocationEnricher(resolver: resolver)
        let photos = [photo(id: "a1", coordinate: coordinateA), photo(id: "undated", coordinate: nil)]

        let result = await enricher.enrich(photos: photos)
        #expect(result.photos.count == 2)
        #expect(!result.warnings.isEmpty)
        #expect(result.photos.allSatisfy { $0.place == nil })
    }

    @Test func everyPhotoInAClusterGetsTheSamePlace() async {
        let resolver = MockPlaceResolver()
        let enricher = DefaultPhotoLocationEnricher(resolver: resolver)
        let photos = [photo(id: "a1", coordinate: coordinateA), photo(id: "a2", coordinate: coordinateAClose)]

        let result = await enricher.enrich(photos: photos)
        let places = result.photos.compactMap(\.place)
        #expect(places.count == 2)
        #expect(Set(places).count == 1)
    }

    @Test func photoWithoutCoordinateGetsNilPlace() async {
        let resolver = MockPlaceResolver()
        let enricher = DefaultPhotoLocationEnricher(resolver: resolver)
        let photos = [photo(id: "none", coordinate: nil)]

        let result = await enricher.enrich(photos: photos)
        #expect(result.photos.first?.place == nil)
    }
}
