//
//  CollectionStyleResolver.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Implements PHOTO-EDITOR.md § 12.4's priority chain — "Photo override → Collection style →
/// Original" — for a photo's *preset* only. Adjust and Auto Enhance are never part of this
/// resolution: they always come straight from the photo's own recipe, since `CollectionEditStyle`
/// has no Adjust fields at all (§ 3.4 — a collection only ever shares Preset + intensity).
///
/// Pure/no framework imports, so it's usable both by `PhotoEditorViewModel` (to pre-populate a
/// freshly-opened editor with whatever a photo currently inherits) and by any future
/// Album/Event display pipeline that becomes recipe-aware — this resolver doesn't care which.
enum CollectionStyleResolver {
    /// `photoRecipe.inheritsCollectionStyle == false` is what makes a recipe a real "photo
    /// override" (§ 12.3's "Ảnh B"/"Ảnh C") — including a recipe with `presetId == nil`, which is
    /// exactly "Ảnh C: Original," an explicit bypass of the collection style, not the absence of
    /// an opinion.
    static func resolvedPreset(
        photoRecipe: PhotoEditRecipe?,
        collectionStyle: CollectionEditStyle?
    ) -> (presetId: String?, presetIntensity: Float) {
        if let photoRecipe, !photoRecipe.inheritsCollectionStyle {
            return (photoRecipe.presetId, photoRecipe.presetIntensity)
        }
        if let collectionStyle {
            return (collectionStyle.presetId, collectionStyle.presetIntensity)
        }
        return (nil, 0)
    }

    /// The full effective recipe to render for a photo: resolved preset/intensity, combined with
    /// whatever Adjust/Auto-Enhance state the photo's own recipe carries (or `.original` defaults
    /// if it has none).
    static func resolvedRecipe(
        photoId: String,
        photoRecipe: PhotoEditRecipe?,
        collectionStyle: CollectionEditStyle?
    ) -> PhotoEditRecipe {
        let (presetId, presetIntensity) = resolvedPreset(photoRecipe: photoRecipe, collectionStyle: collectionStyle)
        var recipe = photoRecipe ?? .original(photoId: photoId)
        recipe.presetId = presetId
        recipe.presetIntensity = presetIntensity
        return recipe
    }
}
