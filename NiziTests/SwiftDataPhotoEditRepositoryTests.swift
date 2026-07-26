//
//  SwiftDataPhotoEditRepositoryTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData
import Testing
@testable import Nizi

struct SwiftDataPhotoEditRepositoryTests {
    private func makeRepository() throws -> SwiftDataPhotoEditRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MDPhotoEditRecipe.self, configurations: configuration)
        return SwiftDataPhotoEditRepository(modelContainer: container)
    }

    private func makeRecipe(photoId: String = "photo-1", createdAt: Date = Date(timeIntervalSince1970: 1000)) -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.original(photoId: photoId, now: createdAt)
        recipe.presetId = "warm-memory"
        recipe.presetIntensity = 0.65
        recipe.adjustments.exposure = 0.08
        return recipe
    }

    @Test
    func getRecipeReturnsNilWhenNeverSaved() async throws {
        let repository = try makeRepository()
        let recipe = try await repository.getRecipe(photoId: "photo-1")
        #expect(recipe == nil)
    }

    @Test
    func savingPersistsIt() async throws {
        let repository = try makeRepository()
        try await repository.saveRecipe(makeRecipe())

        let loaded = try await repository.getRecipe(photoId: "photo-1")
        #expect(loaded?.presetId == "warm-memory")
        #expect(loaded?.presetIntensity == 0.65)
        #expect(loaded?.adjustments.exposure == 0.08)
    }

    @Test
    func updateDoesNotCreateADuplicateRowAndPreservesCreatedAt() async throws {
        let repository = try makeRepository()
        let original = makeRecipe(createdAt: Date(timeIntervalSince1970: 1000))
        try await repository.saveRecipe(original)

        var edited = original
        edited.presetIntensity = 0.9
        edited.updatedAt = Date(timeIntervalSince1970: 5000)
        try await repository.saveRecipe(edited)

        let loaded = try await repository.getRecipe(photoId: "photo-1")
        #expect(loaded?.presetIntensity == 0.9)
        #expect(loaded?.createdAt == Date(timeIntervalSince1970: 1000))
        #expect(loaded?.updatedAt == Date(timeIntervalSince1970: 5000))
    }

    @Test
    func adjustmentsRoundTripThroughTheEncodedBlob() async throws {
        let repository = try makeRepository()
        var recipe = makeRecipe()
        recipe.adjustments = PhotoAdjustments(exposure: 0.1, contrast: -0.2, highlights: 0.3, shadows: -0.4, warmth: 0.05, saturation: -0.15)
        try await repository.saveRecipe(recipe)

        let loaded = try await repository.getRecipe(photoId: "photo-1")
        #expect(loaded?.adjustments == recipe.adjustments)
    }

    @Test
    func deleteRemovesTheRow() async throws {
        let repository = try makeRepository()
        try await repository.saveRecipe(makeRecipe())
        try await repository.deleteRecipe(photoId: "photo-1")

        let loaded = try await repository.getRecipe(photoId: "photo-1")
        #expect(loaded == nil)
    }

    @Test
    func deletingAPhotoWithNoSavedRecipeIsANoOp() async throws {
        let repository = try makeRepository()
        try await repository.deleteRecipe(photoId: "never-saved")
        // No throw is the assertion here.
    }

    @Test
    func recipesForDifferentPhotosAreIndependent() async throws {
        let repository = try makeRepository()
        try await repository.saveRecipe(makeRecipe(photoId: "photo-1"))
        try await repository.saveRecipe(makeRecipe(photoId: "photo-2"))

        try await repository.deleteRecipe(photoId: "photo-1")

        #expect(try await repository.getRecipe(photoId: "photo-1") == nil)
        #expect(try await repository.getRecipe(photoId: "photo-2") != nil)
    }
}
