//
//  PhotoEditRecipe.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// The one thing Photo Editor ever persists for a photo — never pixels, never a modified copy of
/// the original asset (PHOTO-EDITOR.md § 3.1, § 13.1). Full-resolution rendering only ever happens
/// on demand (preview, export, share, photobook) by replaying this recipe against the original.
struct PhotoEditRecipe: Codable, Equatable, Sendable {
    let photoId: String

    var presetId: String?
    var presetIntensity: Float

    var adjustments: PhotoAdjustments

    var autoEnhanceApplied: Bool
    var autoEnhanceVersion: String?

    /// Whether this photo's preset should come from its Album/Event's `CollectionEditStyle`
    /// (`true`) or is a full override that ignores it (`false`) — see § 12.4's priority chain.
    /// Defaults to `true`: a photo with no recipe of its own always inherits.
    var inheritsCollectionStyle: Bool

    var createdAt: Date
    var updatedAt: Date

    /// The recipe for a photo nobody has ever edited — no preset, zero Adjust, nothing to undo.
    static func original(photoId: String, now: Date = Date()) -> PhotoEditRecipe {
        PhotoEditRecipe(
            photoId: photoId,
            presetId: nil,
            presetIntensity: 0,
            adjustments: .identity,
            autoEnhanceApplied: false,
            autoEnhanceVersion: nil,
            inheritsCollectionStyle: true,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Compares every field except the timestamps — used to detect "did the user actually change
    /// anything" (`PhotoEditSession.hasUnsavedChanges`) without a false positive from `updatedAt`
    /// alone having moved.
    func hasSameContent(as other: PhotoEditRecipe) -> Bool {
        photoId == other.photoId
            && presetId == other.presetId
            && presetIntensity == other.presetIntensity
            && adjustments == other.adjustments
            && autoEnhanceApplied == other.autoEnhanceApplied
            && autoEnhanceVersion == other.autoEnhanceVersion
            && inheritsCollectionStyle == other.inheritsCollectionStyle
    }

    var isUnedited: Bool {
        hasSameContent(as: .original(photoId: photoId, now: createdAt))
    }
}
