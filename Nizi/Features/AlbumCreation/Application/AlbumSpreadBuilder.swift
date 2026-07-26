//
//  AlbumSpreadBuilder.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Splits each `AlbumPhotoGroup` into one or more `AlbumPlanningSpread`s of 2–6 photos. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 13–14.
///
/// Deliberately does **not** merge photos across two *different* input groups (beyond what
/// `AlbumPhotoGrouper` already did for singleton events) — every group `AlbumPhotoGrouper`
/// produces already has ≥ 2 photos, so it can always form at least one valid Spread on its own.
/// § 13.4's cross-event opportunistic merge ("Event A 2 ảnh + Event B 3 ảnh → one Spread") is
/// explicitly a soft preference in the spec ("đây là ưu tiên, không phải ràng buộc tuyệt đối"),
/// not a hard requirement, and the spec's own counter-example ("không ghép chỉ để đạt đủ 6 ảnh")
/// shows it's easy to over-merge incorrectly — keeping every Spread sourced from one original
/// group (or one merged-singleton group) is simpler, fully satisfies every *hard* rule (no
/// Spread under 2 or over 6, an Event's photos stay together, a large Event splits into
/// consecutive Spreads), and stays deterministic without inventing an unspecified "how close in
/// time is close enough" threshold.
protocol AlbumSpreadBuilding {
    func buildSpreads(from groupedPhotos: [AlbumPhotoGroup]) -> [AlbumPlanningSpread]
}

struct DefaultAlbumSpreadBuilder: AlbumSpreadBuilding {
    func buildSpreads(from groupedPhotos: [AlbumPhotoGroup]) -> [AlbumPlanningSpread] {
        groupedPhotos.flatMap { group -> [AlbumPlanningSpread] in
            let sizes = Self.distributeSpreadSizes(photoCount: group.photos.count)
            var spreads: [AlbumPlanningSpread] = []
            var cursor = 0
            for (index, size) in sizes.enumerated() {
                let slice = Array(group.photos[cursor..<(cursor + size)])
                cursor += size
                spreads.append(AlbumPlanningSpread(id: "\(group.id)-spread-\(index)", sourceEventIds: group.eventIds, photos: slice))
            }
            return spreads
        }
    }

    /// § 14.1 — smallest Spread count such that every Spread has 2–6 photos, sizes as even as
    /// possible. Matches every worked example in the spec (7→4+3, 13→5+4+4, 15→5+5+5, 17→6+6+5, …).
    static func distributeSpreadSizes(photoCount: Int) -> [Int] {
        guard photoCount > 0 else { return [] }
        guard photoCount > 6 else { return [photoCount] }

        var spreadCount = Int((Double(photoCount) / 6.0).rounded(.up))
        while spreadCount > 1, photoCount / spreadCount < 2 {
            spreadCount -= 1
        }

        let base = photoCount / spreadCount
        let remainder = photoCount % spreadCount
        var sizes = Array(repeating: base, count: spreadCount)
        for i in 0..<remainder { sizes[i] += 1 }
        return sizes
    }
}
