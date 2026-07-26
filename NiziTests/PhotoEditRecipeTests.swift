//
//  PhotoEditRecipeTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct PhotoEditRecipeTests {
    @Test
    func originalRecipeIsUnedited() {
        let recipe = PhotoEditRecipe.original(photoId: "p1")
        #expect(recipe.isUnedited)
        #expect(recipe.presetId == nil)
        #expect(recipe.presetIntensity == 0)
        #expect(recipe.adjustments == .identity)
        #expect(!recipe.autoEnhanceApplied)
        #expect(recipe.inheritsCollectionStyle)
    }

    @Test
    func hasSameContentIgnoresTimestamps() {
        let now = Date()
        var later = PhotoEditRecipe.original(photoId: "p1", now: now)
        later.updatedAt = now.addingTimeInterval(3600)

        let original = PhotoEditRecipe.original(photoId: "p1", now: now)
        #expect(original.hasSameContent(as: later))
        #expect(original != later) // updatedAt differs, so value equality still fails
    }

    @Test
    func hasSameContentDetectsRealChanges() {
        let recipe = PhotoEditRecipe.original(photoId: "p1")
        var edited = recipe
        edited.presetId = "warm-memory"
        edited.presetIntensity = 0.65

        #expect(!recipe.hasSameContent(as: edited))
    }

    @Test
    func codableRoundTrip() throws {
        var recipe = PhotoEditRecipe.original(photoId: "p1")
        recipe.presetId = "warm-memory"
        recipe.presetIntensity = 0.65
        recipe.adjustments.exposure = 0.08
        recipe.autoEnhanceApplied = true
        recipe.autoEnhanceVersion = "1"
        recipe.inheritsCollectionStyle = false

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: data)
        #expect(decoded == recipe)
    }
}
