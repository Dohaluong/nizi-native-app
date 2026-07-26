//
//  PhotoLocationEnricher.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import CoreLocation

struct PhotoLocationEnrichmentResult {
    let photos: [AlbumPlanningPhoto]
    let resolvedPlaces: [PhotoPlace]
    let warnings: [AlbumPlanningLogEntry]
}

/// Orchestrates clustering → cache lookup → reverse geocoding → assigning `PhotoPlace` back onto
/// every photo in a cluster. Never geocodes twice for the same cluster (§ 4.8: "Không gọi reverse
/// geocoding cho từng ảnh nếu chúng cùng cluster"), and a single cluster's geocoding failure only
/// produces a warning — it never fails the whole enrichment (§ 4.5).
protocol PhotoLocationEnriching {
    func enrich(photos: [AlbumPlanningPhoto]) async -> PhotoLocationEnrichmentResult
}

struct DefaultPhotoLocationEnricher: PhotoLocationEnriching {
    private let clusterer: PhotoLocationClustering
    private let resolver: PhotoPlaceResolving
    private let cache: PhotoPlaceCaching
    private let maximumDistance: CLLocationDistance

    init(
        clusterer: PhotoLocationClustering = DefaultPhotoLocationClusterer(),
        resolver: PhotoPlaceResolving,
        cache: PhotoPlaceCaching = InMemoryPhotoPlaceCache(),
        maximumDistance: CLLocationDistance = DefaultPhotoLocationClusterer.defaultMaximumDistance
    ) {
        self.clusterer = clusterer
        self.resolver = resolver
        self.cache = cache
        self.maximumDistance = maximumDistance
    }

    func enrich(photos: [AlbumPlanningPhoto]) async -> PhotoLocationEnrichmentResult {
        let clusters = clusterer.clusters(from: photos, maximumDistance: maximumDistance)

        var placesByPhotoId: [String: PhotoPlace] = [:]
        var resolvedPlaces: [PhotoPlace] = []
        var warnings: [AlbumPlanningLogEntry] = []

        // Resolved one cluster at a time — a low, simple concurrency bound (§ 11: "tránh gọi
        // nhiều geocoder request song song không kiểm soát", "Không cần xây queue phức tạp").
        for cluster in clusters {
            let cacheKey = PhotoPlaceCacheKey(coordinate: cluster.representativeCoordinate)

            if let cached = await cache.place(for: cacheKey) {
                for photoId in cluster.photoIds { placesByPhotoId[photoId] = cached }
                resolvedPlaces.append(cached)
                continue
            }

            do {
                let place = try await resolver.resolvePlace(for: cluster.representativeCoordinate)
                await cache.store(place, for: cacheKey)
                for photoId in cluster.photoIds { placesByPhotoId[photoId] = place }
                resolvedPlaces.append(place)
            } catch {
                warnings.append(
                    AlbumPlanningLogEntry(
                        stage: .location, level: .warning, subjectId: cluster.id,
                        code: "place_resolution_failed",
                        message: "Could not resolve a place for \(cluster.photoIds.count) photo(s).",
                        metadata: ["clusterId": cluster.id, "photoCount": "\(cluster.photoIds.count)"]
                    )
                )
            }
        }

        let enrichedPhotos = photos.map { photo -> AlbumPlanningPhoto in
            var updated = photo
            updated.place = placesByPhotoId[photo.id]
            return updated
        }

        return PhotoLocationEnrichmentResult(photos: enrichedPhotos, resolvedPlaces: resolvedPlaces, warnings: warnings)
    }
}
