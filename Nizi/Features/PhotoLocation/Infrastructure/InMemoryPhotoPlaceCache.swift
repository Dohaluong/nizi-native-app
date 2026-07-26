//
//  InMemoryPhotoPlaceCache.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// In-memory only this sprint (§ 4.6: "Không cần persistence nếu làm tăng phạm vi đáng kể") — an
/// `actor` conforming to `PhotoPlaceCaching` so a persistent-backed cache can replace this later
/// without any caller changing.
actor InMemoryPhotoPlaceCache: PhotoPlaceCaching {
    private var storage: [PhotoPlaceCacheKey: PhotoPlace] = [:]

    func place(for key: PhotoPlaceCacheKey) async -> PhotoPlace? {
        storage[key]
    }

    func store(_ place: PhotoPlace, for key: PhotoPlaceCacheKey) async {
        storage[key] = place
    }
}
