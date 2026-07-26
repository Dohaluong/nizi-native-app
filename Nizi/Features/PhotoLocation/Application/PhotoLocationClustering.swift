//
//  PhotoLocationClustering.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import CoreLocation

/// Groups a set of planning photos by proximity so nearby photos share one reverse-geocode call.
/// Uses `CLLocation.distance(from:)` for the actual geometry per the spec's explicit guidance
/// (docs/specs/SPEC-ALBUM-PLANNER.md § 4.4: "Có thể dùng CLLocation.distance(from:). Không tự
/// viết công thức khoảng cách nếu không cần thiết") — the one place this module's Application
/// layer reaches for Core Location math directly, since it's pure geometry, not a live service.
protocol PhotoLocationClustering {
    func clusters(from photos: [AlbumPlanningPhoto], maximumDistance: CLLocationDistance) -> [PhotoLocationCluster]
}

struct DefaultPhotoLocationClusterer: PhotoLocationClustering {
    static let defaultMaximumDistance: CLLocationDistance = 100

    /// Greedy clustering: walk photos in a fixed deterministic order, and either join the first
    /// existing cluster within `maximumDistance` of a photo's coordinate, or start a new one.
    /// Simple on purpose — Event-sized photo sets are small (§ 4.4: "greedy clustering chấp nhận
    /// được"), and every step below (input order, tie-breaking) is deterministic so the same
    /// input always produces the same clusters.
    func clusters(from photos: [AlbumPlanningPhoto], maximumDistance: CLLocationDistance) -> [PhotoLocationCluster] {
        struct WorkingCluster {
            var representativeCoordinate: PhotoCoordinate
            var representativeDate: Date?
            var photoIds: [String]
        }

        // Deterministic order: creation date (undated last), then photo ID.
        let orderedPhotos = photos
            .filter { $0.coordinate != nil }
            .sorted { lhs, rhs in
                switch (lhs.creationDate, rhs.creationDate) {
                case let (l?, r?) where l != r: return l < r
                case (nil, .some): return false
                case (.some, nil): return true
                default: return lhs.id < rhs.id
                }
            }

        var working: [WorkingCluster] = []

        for photo in orderedPhotos {
            guard let coordinate = photo.coordinate else { continue }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

            if let matchIndex = working.firstIndex(where: { candidate in
                let candidateLocation = CLLocation(latitude: candidate.representativeCoordinate.latitude, longitude: candidate.representativeCoordinate.longitude)
                return location.distance(from: candidateLocation) <= maximumDistance
            }) {
                working[matchIndex].photoIds.append(photo.id)
            } else {
                working.append(WorkingCluster(representativeCoordinate: coordinate, representativeDate: photo.creationDate, photoIds: [photo.id]))
            }
        }

        // § 4.4 — cluster order by representative photo's date, then lexical cluster ID. Since
        // `working` is built by walking date-ordered photos and appending a new cluster the
        // first time a location is seen, `working`'s own order already *is* representative-date
        // order — assigning IDs in that same order (zero-padded so lexical and numeric order
        // agree past 9 clusters) satisfies both parts of the ordering rule without a second sort.
        return working.enumerated().map { index, cluster in
            PhotoLocationCluster(
                id: String(format: "cluster-%03d", index),
                representativeCoordinate: cluster.representativeCoordinate,
                photoIds: cluster.photoIds
            )
        }
    }
}
