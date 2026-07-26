//
//  AlbumPhotoOrientationSummary.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Informational only (§ 16) — layout-pair scoring looks at each photo against each slot
/// individually, never just these aggregate counts.
struct AlbumPhotoOrientationSummary: Codable, Hashable {
    let landscapeCount: Int
    let portraitCount: Int
    let squareCount: Int

    init(photos: [AlbumPlanningPhoto]) {
        var landscape = 0, portrait = 0, square = 0
        for photo in photos {
            switch photo.orientation {
            case .landscape: landscape += 1
            case .portrait: portrait += 1
            case .square: square += 1
            case nil: break
            }
        }
        landscapeCount = landscape
        portraitCount = portrait
        squareCount = square
    }
}

/// `AlbumLayoutPairSelector`'s output: the winning layout for each page, how the Spread's photos
/// were split between them, and the score that won. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 17.
struct AlbumLayoutPairSelection: Hashable {
    let leftLayout: AlbumPageLayout
    let rightLayout: AlbumPageLayout

    let leftPhotos: [AlbumPlanningPhoto]
    let rightPhotos: [AlbumPlanningPhoto]

    let score: Double
}
