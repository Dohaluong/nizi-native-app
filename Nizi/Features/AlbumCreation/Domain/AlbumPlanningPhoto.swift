//
//  AlbumPlanningPhoto.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Deliberately thin — only the fields the scoring/grouping algorithms in
/// `Features/AlbumCreation/Application` actually read. Not every field is required to have a
/// value; the planner must work with only `id`/`pixelWidth`/`pixelHeight` present (see
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 6).
struct AlbumPhotoEXIF: Codable, Hashable, Sendable {
    let cameraModel: String?
    let lensModel: String?
}

/// The planning-layer photo model — never a `PHAsset`. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 5: "Không truyền trực tiếp `PHAsset` vào core
/// planning nếu có thể tránh," so this module can be unit tested without the Photos framework.
/// An adapter from `PHAsset`/the existing Memory Discovery asset types to this struct is future
/// integration work at the call site, not part of this planning core.
///
/// `coordinate`/`place`/`importance` were added by docs/specs/SPEC-ALBUM-PLANNER.md § 5 — the
/// adapter fills in `coordinate` from `PHAsset.location`; `place` and `importance` start `nil`/
/// `.zero` and are filled in by `PhotoLocationEnriching`/`PhotoImportanceEvaluating` *before*
/// planning starts (never lazily inside the planner itself).
struct AlbumPlanningPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let eventId: String

    let creationDate: Date?

    let pixelWidth: Int
    let pixelHeight: Int

    let coordinate: PhotoCoordinate?
    var place: PhotoPlace?

    let isFavorite: Bool
    let isEdited: Bool

    let burstIdentifier: String?
    let originalFilename: String?
    let exif: AlbumPhotoEXIF?

    var importance: PhotoImportance = .zero

    /// `nil` when `pixelWidth`/`pixelHeight` are non-positive — callers that need this to be
    /// mandatory (e.g. cover selection, slot scoring) should treat `nil` as
    /// `AlbumPlanningError.invalidPhotoDimensions(photoId:)`.
    var orientation: PhotoOrientation? {
        PhotoOrientation.classify(width: pixelWidth, height: pixelHeight)
    }

    var pixelCount: Int {
        pixelWidth * pixelHeight
    }
}
