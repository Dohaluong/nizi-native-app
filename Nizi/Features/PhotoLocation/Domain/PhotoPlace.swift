//
//  PhotoPlace.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// A resolved place name for a coordinate. Deliberately mirrors `CLPlacemark`'s components
/// loosely rather than wrapping it directly — `CLPlacemark` never appears in a domain model
/// (§ 17) — and deliberately does *not* assume every country has the same administrative
/// hierarchy (§ 4.3).
struct PhotoPlace: Codable, Hashable, Sendable {
    let coordinate: PhotoCoordinate

    let name: String?
    let subLocality: String?
    let locality: String?
    let subAdministrativeArea: String?
    let administrativeArea: String?
    let country: String?
    let isoCountryCode: String?

    /// Built once by `PhotoPlaceDisplayNameBuilder` at resolve time — never recomputed ad hoc at
    /// call sites, so every UI/log consumer of a given `PhotoPlace` sees the same text.
    let displayName: String
}
