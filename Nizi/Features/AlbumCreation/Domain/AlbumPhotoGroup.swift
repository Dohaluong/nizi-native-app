//
//  AlbumPhotoGroup.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// One or more Events' photos that should be considered together when building Spreads —
/// `AlbumPhotoGrouper`'s output and `AlbumSpreadBuilder`'s input. Usually one Event, but a
/// single-photo Event gets merged into a neighboring group here (§ 13.3), which is why this
/// carries `eventIds` (plural) rather than a single `eventId`.
struct AlbumPhotoGroup: Identifiable, Hashable {
    let id: String
    let eventIds: [String]
    /// Already sorted by `creationDate` (undated photos last) — see § 12.
    let photos: [AlbumPlanningPhoto]
}

/// One Spread's worth of photos, still undivided between its two pages — `AlbumSpreadBuilder`'s
/// output and `AlbumLayoutPairSelector`'s input. Always `2...6` photos (§ 2.3, § 14).
struct AlbumPlanningSpread: Identifiable, Hashable {
    let id: String
    let sourceEventIds: [String]
    let photos: [AlbumPlanningPhoto]
}
