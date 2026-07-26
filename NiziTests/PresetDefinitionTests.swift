//
//  PresetDefinitionTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct PresetDefinitionTests {
    private func makePreset(id: String = "warm-memory", defaultIntensity: Float = 0.65) -> PresetDefinition {
        PresetDefinition(
            id: id, name: "Ký ức ấm", shortName: "Ký ức",
            nameKey: "photoEditor.preset.warm_memory.name", shortNameKey: "photoEditor.preset.warm_memory.shortName",
            lutResource: nil, lutDimension: nil, defaultIntensity: defaultIntensity,
            exposureOffset: 0, contrastOffset: -0.03, saturationOffset: -0.04, warmthOffset: 0.08,
            highlightsOffset: -0.08, shadowsOffset: 0.05,
            grainAmount: 0.12, grainSize: 0.7, bloomAmount: 0.05, bloomRadius: 6,
            vignetteAmount: 0.08, vignetteRadius: 1.2,
            protectSkinTones: true, isMonochrome: false,
            thumbnailAssetName: nil, sortOrder: 1, isActive: true, isPrototype: true
        )
    }

    @Test
    func isOriginalMatchesOriginalId() {
        let original = makePreset(id: PresetDefinition.originalId)
        let other = makePreset(id: "warm-memory")
        #expect(original.isOriginal)
        #expect(!other.isOriginal)
    }

    @Test
    func codableRoundTrip() throws {
        let preset = makePreset()
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(PresetDefinition.self, from: data)
        #expect(decoded == preset)
    }

    /// Regression test: the Preset Tuning Panel added `blacksOffset`/`whitesOffset`/
    /// `vibranceOffset`/`tintOffset`/`sharpnessAmount`/`clarityOffset` to the schema, but every
    /// preset shipped before that tool existed (all 14 entries in the real `presets.json`) has
    /// none of these keys. `PresetDefinition.init(from:)` must decode such JSON without throwing,
    /// defaulting every missing field to `0` rather than a synthesized `Decodable` conformance's
    /// `keyNotFound` failure.
    @Test
    func decodesLegacyJSONMissingTuningFields() throws {
        let legacyJSON = """
        {
            "id": "classic-film", "name": "Classic Film", "shortName": "Classic",
            "nameKey": "photoEditor.preset.classic.name", "shortNameKey": "photoEditor.preset.classic.shortName",
            "lutResource": "fuji-film.cube", "lutDimension": 32, "defaultIntensity": 0.85,
            "exposureOffset": 0, "contrastOffset": 0, "saturationOffset": 0, "warmthOffset": 0,
            "highlightsOffset": 0, "shadowsOffset": 0,
            "grainAmount": 0, "grainSize": 0, "bloomAmount": 0, "bloomRadius": 0,
            "vignetteAmount": 0, "vignetteRadius": 0,
            "protectSkinTones": true, "isMonochrome": false,
            "thumbnailAssetName": null, "sortOrder": 1, "isActive": true, "isPrototype": false
        }
        """
        let decoded = try JSONDecoder().decode(PresetDefinition.self, from: Data(legacyJSON.utf8))
        #expect(decoded.blacksOffset == 0)
        #expect(decoded.whitesOffset == 0)
        #expect(decoded.vibranceOffset == 0)
        #expect(decoded.tintOffset == 0)
        #expect(decoded.sharpnessAmount == 0)
        #expect(decoded.clarityOffset == 0)
    }
}
