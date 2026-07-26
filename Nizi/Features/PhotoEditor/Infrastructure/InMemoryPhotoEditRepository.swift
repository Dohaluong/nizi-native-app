//
//  InMemoryPhotoEditRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Sprint-2 (Editor foundation) placeholder `PhotoEditRepository` — in-memory only, and by
/// default scoped to a single `PhotoEditorView` instance (its default `repository:` argument
/// constructs a fresh one per presentation, so a save does not survive closing and reopening the
/// editor unless a caller explicitly keeps and reuses one instance across presentations). Exists
/// so Save/Cancel can be built and tested end to end before Bước 7 (Persistence) lands
/// `SwiftDataPhotoEditRepository`, without inventing throwaway SwiftData schema ahead of that
/// sprint. Bước 7 swaps the concrete type at the one call site that constructs one
/// (`PhotoEditorView`'s default `repository:` argument); nothing in Domain or Presentation depends
/// on this type directly.
actor InMemoryPhotoEditRepository: PhotoEditRepository {
    private var recipesByPhotoId: [String: PhotoEditRecipe] = [:]

    func getRecipe(photoId: String) async throws -> PhotoEditRecipe? {
        recipesByPhotoId[photoId]
    }

    func saveRecipe(_ recipe: PhotoEditRecipe) async throws {
        recipesByPhotoId[recipe.photoId] = recipe
    }

    func deleteRecipe(photoId: String) async throws {
        recipesByPhotoId.removeValue(forKey: photoId)
    }
}
