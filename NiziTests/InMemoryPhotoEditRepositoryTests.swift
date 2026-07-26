//
//  InMemoryPhotoEditRepositoryTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct InMemoryPhotoEditRepositoryTests {
    @Test
    func getRecipeReturnsNilWhenNeverSaved() async throws {
        let repository = InMemoryPhotoEditRepository()
        let recipe = try await repository.getRecipe(photoId: "p1")
        #expect(recipe == nil)
    }

    @Test
    func saveThenGetRoundTrips() async throws {
        let repository = InMemoryPhotoEditRepository()
        let recipe = PhotoEditRecipe.original(photoId: "p1")
        try await repository.saveRecipe(recipe)

        let fetched = try await repository.getRecipe(photoId: "p1")
        #expect(fetched == recipe)
    }

    @Test
    func saveOverwritesPreviousRecipeForSamePhoto() async throws {
        let repository = InMemoryPhotoEditRepository()
        var recipe = PhotoEditRecipe.original(photoId: "p1")
        try await repository.saveRecipe(recipe)

        recipe.presetId = "warm-memory"
        recipe.presetIntensity = 0.65
        try await repository.saveRecipe(recipe)

        let fetched = try await repository.getRecipe(photoId: "p1")
        #expect(fetched?.presetId == "warm-memory")
    }

    @Test
    func deleteRemovesRecipe() async throws {
        let repository = InMemoryPhotoEditRepository()
        try await repository.saveRecipe(.original(photoId: "p1"))
        try await repository.deleteRecipe(photoId: "p1")

        let fetched = try await repository.getRecipe(photoId: "p1")
        #expect(fetched == nil)
    }
}
