//
//  ApplePhotoPlaceResolver.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import CoreLocation

/// The one place `CLGeocoder` is touched (§ 17: never in Planner). An `actor` so the shared
/// `CLGeocoder` instance is only ever driven from one call at a time — reverse-geocoding a burst
/// of clusters concurrently against a single geocoder instance isn't guaranteed safe otherwise.
actor ApplePhotoPlaceResolver: PhotoPlaceResolving {
    private let geocoder = CLGeocoder()
    private let displayNameBuilder = PhotoPlaceDisplayNameBuilder()

    func resolvePlace(for coordinate: PhotoCoordinate) async throws -> PhotoPlace {
        guard coordinate.isValid else { throw PhotoLocationError.invalidCoordinate }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.reverseGeocodeLocation(location)
        } catch {
            // Diagnostic-only: the real CLError code (e.g. kCLErrorNetwork, which is what
            // CLGeocoder's undocumented rate limit typically surfaces as when many reverse-geocode
            // calls fire back-to-back) gets lost once this rethrows as the generic
            // `PhotoLocationError.geocodingFailed` — log it here, at the source, so a burst of
            // failures during a rebuild can be told apart from a genuinely-unreachable network.
            // Never log the coordinate itself (docs/modules/memory-discovery/ARCHITECTURE.md § 11
            // — GPS is sensitive metadata; event name + error code only).
            let clErrorCode = (error as? CLError)?.code.rawValue
            NiziLogger.discovery.error("apple_photo_place_resolver_geocode_failed clErrorCode=\(clErrorCode.map(String.init) ?? "n/a", privacy: .public)")
            throw PhotoLocationError.geocodingFailed
        }

        guard let placemark = placemarks.first else {
            throw PhotoLocationError.placeNotFound
        }

        return PhotoPlace(
            coordinate: coordinate,
            name: placemark.name,
            subLocality: placemark.subLocality,
            locality: placemark.locality,
            subAdministrativeArea: placemark.subAdministrativeArea,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country,
            isoCountryCode: placemark.isoCountryCode,
            displayName: displayNameBuilder.makeDisplayName(
                name: placemark.name,
                subLocality: placemark.subLocality,
                locality: placemark.locality,
                administrativeArea: placemark.administrativeArea,
                country: placemark.country
            )
        )
    }
}
