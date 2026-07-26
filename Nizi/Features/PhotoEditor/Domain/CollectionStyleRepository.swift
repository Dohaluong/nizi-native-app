//
//  CollectionStyleRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Reads and writes one Album's or Event's `CollectionEditStyle` — never touches individual
/// `PhotoEditRecipe`s or pixels (PHOTO-EDITOR.md § 20.5).
protocol CollectionStyleRepository: Sendable {
    func getStyle(type: CollectionType, id: String) async throws -> CollectionEditStyle?
    func saveStyle(_ style: CollectionEditStyle) async throws
}
