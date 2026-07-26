//
//  PresetTuningJSONTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct PresetTuningJSONTests {
    private func makePreset() -> PresetDefinition {
        PresetDefinition(
            id: "test", name: "Test", shortName: "Test",
            nameKey: "test.name", shortNameKey: "test.shortName",
            lutResource: "fuji-film.cube", lutDimension: 32, defaultIntensity: 0.65,
            exposureOffset: 0.025, contrastOffset: 0.12, saturationOffset: 0.04, warmthOffset: 0.08,
            highlightsOffset: -0.18, shadowsOffset: 0.10,
            blacksOffset: -0.05, whitesOffset: 0.03, vibranceOffset: 0.12, tintOffset: 0,
            grainAmount: 0.08, grainSize: 1, bloomAmount: 0.04, bloomRadius: 8,
            vignetteAmount: 0.10, vignetteRadius: 1.5, sharpnessAmount: 0.06, clarityOffset: 0,
            protectSkinTones: true, isMonochrome: false,
            thumbnailAssetName: nil, sortOrder: 1, isActive: true, isPrototype: false
        )
    }

    /// Every numeric field round-trips through display units without drift, and applying the
    /// round-tripped JSON back onto the original preset reproduces the same offsets.
    @Test
    func presetToJSONToPresetRoundTrips() {
        let preset = makePreset()
        let json = PresetTuningJSON(preset: preset)

        #expect(json.lut == "fuji-film.cube")
        #expect(abs(json.defaultIntensity - 0.65) < 0.001)
        #expect(abs(json.contrast - 12) < 0.01) // contrastOffset 0.12 * 100
        #expect(abs(json.highlights - (-18)) < 0.01)
        #expect(abs(json.exposure - 0.05) < 0.01) // exposureOffset 0.025 * 2.0 EV

        let restored = json.applying(to: preset)
        #expect(abs(restored.contrastOffset - preset.contrastOffset) < 0.0001)
        #expect(abs(restored.exposureOffset - preset.exposureOffset) < 0.0001)
        #expect(abs(restored.vibranceOffset - preset.vibranceOffset) < 0.0001)
        #expect(restored.id == preset.id) // identity fields untouched by `applying(to:)`
    }

    /// The example JSON in the Preset Tuning Panel spec predates `clarityOffset` and omits the
    /// `clarity` key entirely — decoding it must not throw, defaulting `clarity` to `0`.
    @Test
    func decodesJSONMissingClarityKey() throws {
        let json = """
        {
          "lut": "Fuji.cube",
          "defaultIntensity": 0.65,
          "exposure": 0.05,
          "contrast": 12,
          "highlights": -18,
          "shadows": 10,
          "whites": 3,
          "blacks": -5,
          "warmth": 8,
          "tint": 0,
          "saturation": 4,
          "vibrance": 12,
          "bloom": 4,
          "grain": 8,
          "vignette": 10,
          "sharpness": 6
        }
        """
        let decoded = try JSONDecoder().decode(PresetTuningJSON.self, from: Data(json.utf8))
        #expect(decoded.clarity == 0)
        #expect(decoded.lut == "Fuji.cube")
        #expect(decoded.vibrance == 12)
    }

    @Test
    func prettyPrintedProducesParseableJSON() throws {
        let json = PresetTuningJSON(preset: makePreset())
        let text = json.prettyPrinted()
        let reparsed = try JSONDecoder().decode(PresetTuningJSON.self, from: Data(text.utf8))
        #expect(reparsed == json)
    }
}
