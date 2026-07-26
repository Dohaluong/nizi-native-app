//
//  InMemoryCollectionStyleRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// In-memory-only `CollectionStyleRepository` — same role `InMemoryPhotoEditRepository` plays for
/// `PhotoEditRepository`: `PhotoEditorView`'s harmless default and a dependency for tests/previews
/// that don't need a `ModelContainer`. Never actually exercised in practice, since the save-scope
/// sheet that would call into this is only shown when `EditorContext.sourceType != .standalone`,
/// and every real Album/Event call site passes a `SwiftDataCollectionStyleRepository` instead.
actor InMemoryCollectionStyleRepository: CollectionStyleRepository {
    private var stylesByKey: [String: CollectionEditStyle] = [:]

    func getStyle(type: CollectionType, id: String) async throws -> CollectionEditStyle? {
        stylesByKey["\(type.rawValue):\(id)"]
    }

    func saveStyle(_ style: CollectionEditStyle) async throws {
        stylesByKey["\(style.collectionType.rawValue):\(style.collectionId)"] = style
    }
}
