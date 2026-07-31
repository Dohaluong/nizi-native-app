//
//  LocationContext.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Where a coordinate sits relative to the user's everyday life (SPEC § 13). Derived on demand,
/// never persisted — cheap to recompute from `HomeAnchor`/`[FamiliarPlace]` whenever needed.
enum LocationContext: Equatable {
    case home
    case familiar
    case local
    case away
    case unknown
}

/// Pure derivation, reusing `EventDiscoveryEngine.haversineDistanceKm` rather than a second
/// distance primitive.
enum LocationContextResolver {
    static func resolve(
        latitude: Double?,
        longitude: Double?,
        home: HomeAnchor?,
        familiarPlaces: [FamiliarPlace],
        config: EventDiscoveryConfig
    ) -> LocationContext {
        guard let latitude, let longitude else { return .unknown }

        // Familiar-place matching works even before Home has been established (e.g. early in a
        // library's history) — only the local/away distinction genuinely needs a Home reference,
        // so that's the only branch gated on `home` being known.
        if let home {
            let distanceToHomeKm = EventDiscoveryEngine.haversineDistanceKm(
                lat1: home.centerLatitude, lon1: home.centerLongitude, lat2: latitude, lon2: longitude
            )
            if distanceToHomeKm * 1000 <= config.familiarPlaceRadiusMeters {
                return .home
            }
        }

        for place in familiarPlaces {
            let distanceKm = EventDiscoveryEngine.haversineDistanceKm(
                lat1: place.centerLatitude, lon1: place.centerLongitude, lat2: latitude, lon2: longitude
            )
            if distanceKm * 1000 <= config.familiarPlaceRadiusMeters {
                return .familiar
            }
        }

        guard let home else { return .unknown }
        let distanceToHomeKm = EventDiscoveryEngine.haversineDistanceKm(
            lat1: home.centerLatitude, lon1: home.centerLongitude, lat2: latitude, lon2: longitude
        )
        return distanceToHomeKm <= config.localRadiusKm ? .local : .away
    }
}
