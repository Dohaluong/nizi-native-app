//
//  MDCollectionEditStyle.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData

/// SwiftData row for one Album's or Event's `CollectionEditStyle`. `collectionKey` (`"album:<id>"`/
/// `"event:<id>"`) is the unique lookup key rather than `collectionId` alone, since Album and Event
/// ids aren't guaranteed to live in disjoint namespaces (`AlbumDraft.id` is a `String`, `PhotoEvent.
/// id` a `UUID` rendered as a string) — same reasoning `MDAlbumDraft`/`MDLocalAsset` apply to their
/// own unique columns.
@Model
final class MDCollectionEditStyle {
    @Attribute(.unique) var collectionKey: String
    var collectionType: String
    var collectionId: String
    var presetId: String?
    var presetIntensity: Float = 0
    var autoEnhanceEachPhoto: Bool = false
    var createdAt: Date
    var updatedAt: Date

    init(style: CollectionEditStyle) {
        collectionKey = Self.key(type: style.collectionType, id: style.collectionId)
        collectionType = style.collectionType.rawValue
        collectionId = style.collectionId
        presetId = style.presetId
        presetIntensity = style.presetIntensity
        autoEnhanceEachPhoto = style.autoEnhanceEachPhoto
        createdAt = style.createdAt
        updatedAt = style.updatedAt
    }

    func apply(_ style: CollectionEditStyle) {
        presetId = style.presetId
        presetIntensity = style.presetIntensity
        autoEnhanceEachPhoto = style.autoEnhanceEachPhoto
        // createdAt is deliberately never overwritten here.
        updatedAt = style.updatedAt
    }

    func decodedStyle() -> CollectionEditStyle? {
        guard let type = CollectionType(rawValue: collectionType) else { return nil }
        return CollectionEditStyle(
            collectionType: type,
            collectionId: collectionId,
            presetId: presetId,
            presetIntensity: presetIntensity,
            autoEnhanceEachPhoto: autoEnhanceEachPhoto,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func key(type: CollectionType, id: String) -> String {
        "\(type.rawValue):\(id)"
    }
}
