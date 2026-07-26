//
//  CollectionEditStyle.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Which kind of collection a `CollectionEditStyle` belongs to — Album and Event share the exact
/// same style shape (PHOTO-EDITOR.md § 13.2), so one model serves both rather than two near-
/// duplicate ones.
enum CollectionType: String, Codable, Equatable, Sendable {
    case album
    case event
}

/// An Album's or Event's default look — never per-photo Adjust values, only Preset + intensity
/// (§ 3.4: "Áp dụng toàn bộ chỉ mặc định áp phong cách"). A single row here is what lets every
/// photo in the collection inherit the same style without duplicating a `PhotoEditRecipe` per
/// photo (§ 9: "Không nhân bản recipe giống nhau cho mọi ảnh nếu có thể lưu style ở cấp
/// Album/Event").
struct CollectionEditStyle: Codable, Equatable, Sendable {
    let collectionType: CollectionType
    let collectionId: String

    var presetId: String?
    var presetIntensity: Float

    /// § 11.5 — when `true`, applying this style also runs Auto Enhance independently for every
    /// photo in the collection (never one shared result copied to all of them).
    var autoEnhanceEachPhoto: Bool

    var createdAt: Date
    var updatedAt: Date
}
