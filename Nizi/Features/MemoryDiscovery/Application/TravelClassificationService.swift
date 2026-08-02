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

        // Diagnostic-only summary — one line to see, at a glance, how many trips actually got a
        // real place name this run vs. how many didn't (and see it shrink/grow across reruns
        // without having to count individual per-trip log lines).
        let resolvedCount = classified.filter { $0.primaryPlaceName != nil }.count
        NiziLogger.discovery.info("trip_classification_completed total=\(classified.count, privacy: .public) resolved=\(resolvedCount, privacy: .public) unresolved=\(classified.count - resolvedCount, privacy: .public)")

        return classified
    }

    private func classify(trip: PhotoTrip, homeCountryCode: String?) async -> PhotoTrip {
        var trip = trip
        trip.travelContext.homeCountryCode = homeCountryCode

        // "Day Trip" (no overnight stay, and not a provisional international candidate) used to
        // skip geocoding entirely (SPEC § 29) to avoid a network call for every trivial away-from-
        // home cluster. Trip Eligibility V1 (SPRINT-NEXT § 5-9) now already requires a day trip to
        // clear a real distance/duration/session-count bar before it exists as a `PhotoTrip` at
        // all, so by the time classification runs it's never a trivial case — skipping geocoding
        // just meant a real, eligible day trip's place name was never resolved. Always attempt
        // geocoding when a coordinate is available; `isDayTrip` only decides the final
        // classification label, not whether a place name gets resolved.
        let isProvisionalInternationalCandidate = trip.travelContext.eligibilityReasons
            .contains(TripEligibilityReason.internationalCandidate.rawValue)
        let isDayTrip = trip.travelContext.overnightCount == 0 && !isProvisionalInternationalCandidate

        // Split out so a trip that never had a resolvable coordinate at all (no session in any of
        // its Events had GPS) can be told apart, in the logs, from one that had a coordinate but
        // whose geocode attempt failed (already logged inside `resolvePlace`/
        // `ApplePhotoPlaceResolver` — see those for the real CLError detail).
        guard let latitude = trip.primaryLatitude, let longitude = trip.primaryLongitude,
              let coordinate = PhotoCoordinate(latitude: latitude, longitude: longitude)
        else {
            NiziLogger.discovery.info("trip_classification_no_coordinate tripID=\(trip.id, privacy: .public)")
            trip.classification = isDayTrip ? .dayTrip : .unknown
            return trip
        }

        guard let place = await resolvePlace(for: coordinate) else {
            trip.classification = isDayTrip ? .dayTrip : .unknown
            return trip
        }

        trip.primaryPlaceName = place.displayName
        trip.primaryCountryCode = place.isoCountryCode
        if let countryCode = place.isoCountryCode {
            trip.travelContext.countryCodes = [countryCode]
        }

        if isDayTrip {
            trip.classification = .dayTrip
            return trip
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
