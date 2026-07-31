//
//  TravelClassificationService.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// The one place this module reverse-geocodes for Trip classification (SPRINT-SMART-EVENT-
/// TRAVEL-DISCOVERY § 27-31) — resolves at most one coordinate per Trip plus the Home coordinate
/// once, never per-photo, caching through the same `PhotoPlaceResolving`/`PhotoPlaceCaching`
/// protocols `PhotoLocation`'s own `DefaultPhotoLocationEnricher` already uses. Depending on
/// `PhotoLocation`'s Application-layer protocols here (not from `MemoryDiscovery/Domain`) mirrors
/// the one existing cross-feature precedent, `AlbumDraftPlanner`'s dependency on
/// `PhotoLocationEnriching`.
final class TravelClassificationService {
    private let placeResolver: PhotoPlaceResolving
    private let placeCache: PhotoPlaceCaching

    init(
        placeResolver: PhotoPlaceResolving = ApplePhotoPlaceResolver(),
        placeCache: PhotoPlaceCaching = InMemoryPhotoPlaceCache()
    ) {
        self.placeResolver = placeResolver
        self.placeCache = placeCache
    }

    func classify(trips: [PhotoTrip], home: HomeAnchor?) async -> [PhotoTrip] {
        guard !trips.isEmpty else { return [] }

        var homeCountryCode: String?
        if let home, let homeCoordinate = PhotoCoordinate(latitude: home.centerLatitude, longitude: home.centerLongitude) {
            homeCountryCode = await resolvePlace(for: homeCoordinate)?.isoCountryCode
        }

        var classified: [PhotoTrip] = []
        classified.reserveCapacity(trips.count)
        for trip in trips {
            classified.append(await classify(trip: trip, homeCountryCode: homeCountryCode))
        }
        return classified
    }

    private func classify(trip: PhotoTrip, homeCountryCode: String?) async -> PhotoTrip {
        var trip = trip
        trip.travelContext.homeCountryCode = homeCountryCode

        // No overnight stay and already back — a Day Trip, no geocoding needed at all (SPEC § 29).
        guard trip.travelContext.overnightCount > 0 else {
            trip.classification = .dayTrip
            return trip
        }

        guard let latitude = trip.primaryLatitude, let longitude = trip.primaryLongitude,
              let coordinate = PhotoCoordinate(latitude: latitude, longitude: longitude),
              let place = await resolvePlace(for: coordinate)
        else {
            trip.classification = .unknown
            return trip
        }

        trip.primaryPlaceName = place.displayName
        trip.primaryCountryCode = place.isoCountryCode
        if let countryCode = place.isoCountryCode {
            trip.travelContext.countryCodes = [countryCode]
        }

        switch (place.isoCountryCode, homeCountryCode) {
        case let (tripCode?, homeCode?) where tripCode == homeCode:
            trip.classification = .domesticTrip
        case (.some, .some):
            trip.classification = .internationalTrip
        default:
            trip.classification = .unknown
        }

        return trip
    }

    private func resolvePlace(for coordinate: PhotoCoordinate) async -> PhotoPlace? {
        let key = PhotoPlaceCacheKey(coordinate: coordinate)
        if let cached = await placeCache.place(for: key) {
            return cached
        }
        do {
            let place = try await placeResolver.resolvePlace(for: coordinate)
            await placeCache.store(place, for: key)
            return place
        } catch {
            NiziLogger.discovery.error("travel_classification_geocode_failed error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
