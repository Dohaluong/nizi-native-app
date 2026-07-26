//
//  AlbumPrimaryPlaceResolver.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Picks the one "primary place" to represent a set of photos — used at Page, Spread, and Album
/// scope. See docs/specs/SPEC-ALBUM-PLANNER.md § 9.
enum AlbumPrimaryPlaceResolver {
    /// § 9.2 / § 9.3 — Page and Spread scope share the same rule: most frequent place; ties broken
    /// by the hero photo's place, then the highest-importance photo's place, then lexical
    /// `displayName` order.
    static func resolve(photos: [AlbumPlanningPhoto], heroPhotoId: String?) -> PhotoPlace? {
        let places = photos.compactMap(\.place)
        guard !places.isEmpty else { return nil }

        let counts = Dictionary(grouping: places, by: { $0 })
            .mapValues(\.count)
        let maxCount = counts.values.max() ?? 0
        let topPlaces = Set(counts.filter { $0.value == maxCount }.keys)
        guard topPlaces.count > 1 else { return topPlaces.first }

        if let heroPhotoId, let heroPlace = photos.first(where: { $0.id == heroPhotoId })?.place, topPlaces.contains(heroPlace) {
            return heroPlace
        }

        if let mostImportant = photos
            .filter({ if let place = $0.place { return topPlaces.contains(place) } else { return false } })
            .max(by: { $0.importance.totalScore < $1.importance.totalScore })?.place {
            return mostImportant
        }

        return topPlaces.sorted { $0.displayName < $1.displayName }.first
    }

    /// § 9.4 — Album scope: majority place across every photo → cover photo's place → the main
    /// Event's place → `nil`. Deliberately does *not* fall back to a single outlier photo's
    /// location when most of the Album is somewhere else.
    static func resolveAlbumPlace(
        photos: [AlbumPlanningPhoto],
        coverPhotoId: String,
        mainEventPlace: PhotoPlace?
    ) -> PhotoPlace? {
        let places = photos.compactMap(\.place)
        if !places.isEmpty {
            let counts = Dictionary(grouping: places, by: { $0 }).mapValues(\.count)
            let maxCount = counts.values.max() ?? 0
            let topPlaces = counts.filter { $0.value == maxCount }.keys.sorted { $0.displayName < $1.displayName }
            if let majorityPlace = topPlaces.first {
                return majorityPlace
            }
        }
        if let coverPlace = photos.first(where: { $0.id == coverPhotoId })?.place {
            return coverPlace
        }
        return mainEventPlace
    }
}
