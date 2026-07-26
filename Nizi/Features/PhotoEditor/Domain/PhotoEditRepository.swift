//
//  PhotoEditRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Reads and writes one photo's `PhotoEditRecipe` — never touches pixels or the Photos Library
/// (PHOTO-EDITOR.md § 20.4). `Sendable` since every implementation is expected to cross actor
/// boundaries (an `@ModelActor` in production, from Bước 7 onward).
protocol PhotoEditRepository: Sendable {
    func getRecipe(photoId: String) async throws -> PhotoEditRecipe?
    func saveRecipe(_ recipe: PhotoEditRecipe) async throws
    func deleteRecipe(photoId: String) async throws
}
