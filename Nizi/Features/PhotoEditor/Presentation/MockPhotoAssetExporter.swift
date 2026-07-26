//
//  MockPhotoAssetExporter.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// A `PhotoAssetExporting` that never touches the Photos Library — for SwiftUI Previews and
/// standalone QA only (mirrors `MockPhotoRendering`'s role for `PhotoRendering`). Must never be the
/// default in `PhotoEditorView`'s production initializer.
struct MockPhotoAssetExporter: PhotoAssetExporting {
    func exportEditedCopy(photoId: String, recipe: PhotoEditRecipe, renderer: PhotoRendering, deleteOriginal: Bool) async throws -> String {
        try await Task.sleep(nanoseconds: 300_000_000)
        return "mock-exported-\(UUID().uuidString)"
    }
}
