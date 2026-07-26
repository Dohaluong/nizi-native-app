//
//  MDCustomPreset.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData

/// A user-imported preset — the whole `PresetDefinition` is stored as one encoded blob (same
/// "encode the struct, don't flatten it into columns" reasoning `MDPhotoEditRecipe.
/// encodedAdjustments` uses), since nothing here needs to be queried/sorted at the row level;
/// `CustomizablePresetRepository` always loads every row and decodes it. Its `lutResource` points
/// at a `.cube` file copied into `DocumentsCustomLUTFileStore`'s directory, never into the app
/// bundle (which an installed app can't write to).
@Model
final class MDCustomPreset {
    @Attribute(.unique) var presetId: String
    var encodedPreset: Data
    var createdAt: Date

    init(preset: PresetDefinition, createdAt: Date) throws {
        presetId = preset.id
        encodedPreset = try JSONEncoder().encode(preset)
        self.createdAt = createdAt
    }

    func decodedPreset() throws -> PresetDefinition {
        try JSONDecoder().decode(PresetDefinition.self, from: encodedPreset)
    }

    func updateEncodedPreset(_ preset: PresetDefinition) throws {
        encodedPreset = try JSONEncoder().encode(preset)
    }
}
