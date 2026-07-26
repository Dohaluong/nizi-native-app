//
//  CollectionStyleResolverTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct CollectionStyleResolverTests {
    private func albumStyle(presetId: String? = "warm-memory", presetIntensity: Float = 0.65) -> CollectionEditStyle {
        CollectionEditStyle(
            collectionType: .album, collectionId: "album-1", presetId: presetId, presetIntensity: presetIntensity,
            autoEnhanceEachPhoto: false, createdAt: Date(), updatedAt: Date()
        )
    }

    // "Ảnh A" — no recipe of its own at all: inherits the collection's style outright.
    @Test
    func photoWithNoRecipeInheritsTheCollectionStyle() {
        let resolved = CollectionStyleResolver.resolvedPreset(photoRecipe: nil, collectionStyle: albumStyle())
        #expect(resolved.presetId == "warm-memory")
        #expect(resolved.presetIntensity == 0.65)
    }

    // A recipe that exists but is still marked as inheriting (e.g. only Adjust was ever touched)
    // still defers its preset to the collection.
    @Test
    func recipeMarkedAsInheritingStillDefersToTheCollectionStyle() {
        var recipe = PhotoEditRecipe.original(photoId: "p1")
        recipe.inheritsCollectionStyle = true
        recipe.adjustments.exposure = 0.2 // Adjust is photo-specific regardless of inheritance
        let resolved = CollectionStyleResolver.resolvedPreset(photoRecipe: recipe, collectionStyle: albumStyle())
        #expect(resolved.presetId == "warm-memory")
        #expect(resolved.presetIntensity == 0.65)
    }

    // "Ảnh B" — an explicit override with its own different preset/intensity wins outright.
    @Test
    func photoOverrideWinsOverTheCollectionStyle() {
        var recipe = PhotoEditRecipe.original(photoId: "p1")
        recipe.presetId = "warm-memory"
        recipe.presetIntensity = 0.45
        recipe.inheritsCollectionStyle = false
        let resolved = CollectionStyleResolver.resolvedPreset(photoRecipe: recipe, collectionStyle: albumStyle())
        #expect(resolved.presetId == "warm-memory")
        #expect(resolved.presetIntensity == 0.45)
    }

    // "Ảnh C" — an explicit override to Original (presetId nil) also wins, bypassing the
    // collection style entirely rather than falling through to it.
    @Test
    func photoOverrideToOriginalBypassesTheCollectionStyleEntirely() {
        var recipe = PhotoEditRecipe.original(photoId: "p1")
        recipe.inheritsCollectionStyle = false
        let resolved = CollectionStyleResolver.resolvedPreset(photoRecipe: recipe, collectionStyle: albumStyle())
        #expect(resolved.presetId == nil)
        #expect(resolved.presetIntensity == 0)
    }

    @Test
    func noCollectionStyleAndNoRecipeResolvesToOriginal() {
        let resolved = CollectionStyleResolver.resolvedPreset(photoRecipe: nil, collectionStyle: nil)
        #expect(resolved.presetId == nil)
        #expect(resolved.presetIntensity == 0)
    }

    @Test
    func resolvedRecipeCombinesResolvedPresetWithThePhotosOwnAdjustments() {
        var recipe = PhotoEditRecipe.original(photoId: "p1")
        recipe.adjustments.exposure = 0.3
        recipe.adjustments.saturation = -0.1
        recipe.inheritsCollectionStyle = true

        let resolved = CollectionStyleResolver.resolvedRecipe(photoId: "p1", photoRecipe: recipe, collectionStyle: albumStyle())
        #expect(resolved.presetId == "warm-memory")
        #expect(resolved.presetIntensity == 0.65)
        #expect(resolved.adjustments.exposure == 0.3)
        #expect(resolved.adjustments.saturation == -0.1)
    }

    @Test
    func resolvedRecipeForAPhotoWithNoRecipeAtAllStartsFromOriginalAdjustments() {
        let resolved = CollectionStyleResolver.resolvedRecipe(photoId: "p1", photoRecipe: nil, collectionStyle: albumStyle())
        #expect(resolved.presetId == "warm-memory")
        #expect(resolved.adjustments == .identity)
    }
}
