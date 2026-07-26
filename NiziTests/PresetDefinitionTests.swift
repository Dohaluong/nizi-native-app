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
}
