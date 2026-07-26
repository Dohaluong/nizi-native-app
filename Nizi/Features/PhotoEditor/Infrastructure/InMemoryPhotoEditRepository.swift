//
//  InMemoryPhotoEditRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// In-memory-only `PhotoEditRepository` — by default scoped to a single `PhotoEditorView`
/// instance (its default `repository:` argument constructs a fresh one per presentation, so a
/// save does not survive closing and reopening the editor unless a caller explicitly keeps and
/// reuses one instance across presentations). Originated as Sprint 2's stand-in before
/// `SwiftDataPhotoEditRepository` existed; kept on as `PhotoEditorView`'s harmless fallback
/// default and for tests/previews that don't need a `ModelContainer` — every real call site
/// (the standalone harness now, Album/Event in Bước 8) passes a `SwiftDataPhotoEditRepository`
/// explicitly instead.
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
