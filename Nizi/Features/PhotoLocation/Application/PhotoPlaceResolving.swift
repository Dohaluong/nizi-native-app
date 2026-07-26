//
//  PhotoPlaceResolving.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Reverse geocoding, abstracted so nothing above Infrastructure ever imports `CLGeocoder`
/// directly. `ApplePhotoPlaceResolver` (Infrastructure) is the only implementation this sprint.
protocol PhotoPlaceResolving: Sendable {
    func resolvePlace(for coordinate: PhotoCoordinate) async throws -> PhotoPlace
}

/// Caches resolved places by a rounded coordinate bucket (§ 4.6), not exact `Double`s, so nearby
/// but not-quite-identical coordinates still hit the cache.
protocol PhotoPlaceCaching: Sendable {
    func place(for key: PhotoPlaceCacheKey) async -> PhotoPlace?
    func store(_ place: PhotoPlace, for key: PhotoPlaceCacheKey) async
}

struct PhotoPlaceCacheKey: Hashable, Codable, Sendable {
    let latitudeBucket: Int
    let longitudeBucket: Int

    /// 4 decimal places (~11m at the equator) — cache-only precision, never used as the
    /// clustering distance itself (§ 4.6: "Mức này chỉ dùng cache, không dùng làm cluster chính xác").
    init(coordinate: PhotoCoordinate) {
        latitudeBucket = Int((coordinate.latitude * 10_000).rounded())
        longitudeBucket = Int((coordinate.longitude * 10_000).rounded())
    }
}
