//
//  SwiftDataPhotoEditRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData

/// Production `PhotoEditRepository` — same `@ModelActor` shape as `SwiftDataAlbumDraftStore`/
/// `SwiftDataMemoryDiscoveryStore`: its own isolated `ModelContext`, constructed on demand from
/// `modelContext.container` at whichever call site opens Photo Editor, never held as a singleton.
/// Bước 2's `InMemoryPhotoEditRepository` is what Photo Editor used before this landed; this is
/// the first repository that actually survives closing and reopening the app.
@ModelActor
actor SwiftDataPhotoEditRepository: PhotoEditRepository {
    func getRecipe(photoId: String) async throws -> PhotoEditRecipe? {
        var descriptor = FetchDescriptor<MDPhotoEditRecipe>(predicate: #Predicate { $0.photoId == photoId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { try $0.decodedRecipe() }
    }

    /// Always updates the existing row in place for this `photoId` — never inserts a second row
    /// for the same photo (mirrors `SwiftDataAlbumDraftStore.updateDraft`'s own "never a duplicate
    /// row for an edit" rule).
    func saveRecipe(_ recipe: PhotoEditRecipe) async throws {
        let photoId = recipe.photoId
        var descriptor = FetchDescriptor<MDPhotoEditRecipe>(predicate: #Predicate { $0.photoId == photoId })
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            try existing.apply(recipe)
        } else {
            modelContext.insert(try MDPhotoEditRecipe(recipe: recipe))
        }
        try modelContext.save()
    }

    func deleteRecipe(photoId: String) async throws {
        var descriptor = FetchDescriptor<MDPhotoEditRecipe>(predicate: #Predicate { $0.photoId == photoId })
        descriptor.fetchLimit = 1
        guard let existing = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }
}
