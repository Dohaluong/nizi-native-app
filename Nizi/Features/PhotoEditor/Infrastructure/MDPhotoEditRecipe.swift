//
//  MDPhotoEditRecipe.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData

/// SwiftData row for one photo's `PhotoEditRecipe` — same shape/discipline as `MDAlbumDraft`:
/// plain columns for the fields a future list/query screen might filter or sort on, plus one
/// encoded blob (`encodedAdjustments`) for the small nested `PhotoAdjustments` struct, so adding a
/// seventh Adjust field later (should that ever happen) never needs a schema migration of its own.
/// Every column has a harmless default so SwiftData's lightweight migration can add this whole
/// model to an existing store without touching any other table (PHOTO-EDITOR.md § 7: "Phải có
/// migration an toàn. Không xóa dữ liệu cũ").
@Model
final class MDPhotoEditRecipe {
    @Attribute(.unique) var photoId: String
    var presetId: String?
    var presetIntensity: Float = 0
    var encodedAdjustments: Data
    var autoEnhanceApplied: Bool = false
    var autoEnhanceVersion: String?
    var inheritsCollectionStyle: Bool = true
    var createdAt: Date
    var updatedAt: Date

    init(recipe: PhotoEditRecipe) throws {
        photoId = recipe.photoId
        presetId = recipe.presetId
        presetIntensity = recipe.presetIntensity
        encodedAdjustments = try JSONEncoder().encode(recipe.adjustments)
        autoEnhanceApplied = recipe.autoEnhanceApplied
        autoEnhanceVersion = recipe.autoEnhanceVersion
        inheritsCollectionStyle = recipe.inheritsCollectionStyle
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
    }

    func apply(_ recipe: PhotoEditRecipe) throws {
        presetId = recipe.presetId
        presetIntensity = recipe.presetIntensity
        encodedAdjustments = try JSONEncoder().encode(recipe.adjustments)
        autoEnhanceApplied = recipe.autoEnhanceApplied
        autoEnhanceVersion = recipe.autoEnhanceVersion
        inheritsCollectionStyle = recipe.inheritsCollectionStyle
        // createdAt is deliberately never overwritten here.
        updatedAt = recipe.updatedAt
    }

    func decodedRecipe() throws -> PhotoEditRecipe {
        let adjustments = try JSONDecoder().decode(PhotoAdjustments.self, from: encodedAdjustments)
        return PhotoEditRecipe(
            photoId: photoId,
            presetId: presetId,
            presetIntensity: presetIntensity,
            adjustments: adjustments,
            autoEnhanceApplied: autoEnhanceApplied,
            autoEnhanceVersion: autoEnhanceVersion,
            inheritsCollectionStyle: inheritsCollectionStyle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
