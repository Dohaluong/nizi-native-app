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
