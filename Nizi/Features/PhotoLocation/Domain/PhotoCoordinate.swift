//
//  PhotoCoordinate.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// A GPS coordinate, decoupled from `CLLocationCoordinate2D` — this module's domain layer never
/// imports Core Location directly (see docs/specs/SPEC-ALBUM-PLANNER.md § 17: "Không để domain
/// model phụ thuộc Core Location").
struct PhotoCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    private static let latitudeRange = -90.0...90.0
    private static let longitudeRange = -180.0...180.0

    var isValid: Bool {
        Self.latitudeRange.contains(latitude) && Self.longitudeRange.contains(longitude)
    }

    /// `nil` if either component is out of range, rather than constructing an invalid value.
    init?(latitude: Double, longitude: Double) {
        guard Self.latitudeRange.contains(latitude), Self.longitudeRange.contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }
}
