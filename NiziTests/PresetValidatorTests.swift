//
//  PresetValidatorTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct PresetValidatorTests {
    private func makePreset(
        id: String,
        defaultIntensity: Float = 0.5,
        lutResource: String? = nil,
        lutDimension: Int? = nil,
        grainAmount: Float = 0,
        sortOrder: Int = 0,
        isActive: Bool = true
    ) -> PresetDefinition {
        PresetDefinition(
            id: id, name: id, shortName: id, nameKey: "key.\(id).name", shortNameKey: "key.\(id).shortName",
            lutResource: lutResource, lutDimension: lutDimension, defaultIntensity: defaultIntensity,
            exposureOffset: 0, contrastOffset: 0, saturationOffset: 0, warmthOffset: 0,
            highlightsOffset: 0, shadowsOffset: 0,
            grainAmount: grainAmount, grainSize: 0, bloomAmount: 0, bloomRadius: 0,
            vignetteAmount: 0, vignetteRadius: 0,
            protectSkinTones: false, isMonochrome: false,
            thumbnailAssetName: nil, sortOrder: sortOrder, isActive: isActive, isPrototype: true
        )
    }

    private func originalPreset(sortOrder: Int = 0) -> PresetDefinition {
        makePreset(id: PresetDefinition.originalId, defaultIntensity: 0, sortOrder: sortOrder)
    }

    @Test
    func validPresetsPassThrough() {
        let presets = [originalPreset(), makePreset(id: "warm-memory", sortOrder: 1)]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.validPresets.count == 2)
        #expect(result.skipped.isEmpty)
        #expect(!result.isMissingOriginal)
    }

    @Test
    func duplicateIdIsSkipped() {
        let presets = [originalPreset(), makePreset(id: "warm-memory", sortOrder: 1), makePreset(id: "warm-memory", sortOrder: 2)]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.validPresets.count == 2)
        #expect(result.skipped.count == 1)
        #expect(result.skipped.first?.id == "warm-memory")
    }

    @Test
    func inactivePresetIsSilentlyExcludedNotSkipped() {
        let presets = [originalPreset(), makePreset(id: "disabled", isActive: false)]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.validPresets.count == 1)
        #expect(result.skipped.isEmpty) // inactive is intentional hiding, not an error
    }

    @Test
    func outOfRangeDefaultIntensityIsSkipped() {
        let presets = [originalPreset(), makePreset(id: "too-strong", defaultIntensity: 1.5)]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.validPresets.count == 1)
        #expect(result.skipped.first?.id == "too-strong")
    }

    @Test
    func negativeGrainAmountIsSkipped() {
        let presets = [originalPreset(), makePreset(id: "bad-grain", grainAmount: -0.1)]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.validPresets.count == 1)
        #expect(result.skipped.first?.id == "bad-grain")
    }

    @Test
    func lutResourceWithoutDimensionIsSkipped() {
        let presets = [originalPreset(), makePreset(id: "no-dimension", lutResource: "x.cube", lutDimension: nil)]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.validPresets.count == 1)
        #expect(result.skipped.first?.id == "no-dimension")
    }

    @Test
    func missingLUTResourceIsSkipped() {
        let presets = [originalPreset(), makePreset(id: "missing-lut", lutResource: "missing.cube", lutDimension: 33)]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in false })
        #expect(result.validPresets.count == 1)
        #expect(result.skipped.first?.id == "missing-lut")
    }

    @Test
    func originalWithNonzeroIntensityIsSkipped() {
        let presets = [originalPreset(sortOrder: 0), makePreset(id: "warm-memory", sortOrder: 1)]
            .map { $0.id == PresetDefinition.originalId ? PresetDefinition(
                id: $0.id, name: $0.name, shortName: $0.shortName, nameKey: $0.nameKey, shortNameKey: $0.shortNameKey,
                lutResource: nil, lutDimension: nil, defaultIntensity: 0.3,
                exposureOffset: 0, contrastOffset: 0, saturationOffset: 0, warmthOffset: 0,
                highlightsOffset: 0, shadowsOffset: 0, grainAmount: 0, grainSize: 0, bloomAmount: 0, bloomRadius: 0,
                vignetteAmount: 0, vignetteRadius: 0, protectSkinTones: false, isMonochrome: false,
                thumbnailAssetName: nil, sortOrder: $0.sortOrder, isActive: true, isPrototype: false
            ) : $0 }
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.isMissingOriginal)
        #expect(result.skipped.contains { $0.id == PresetDefinition.originalId })
    }

    @Test
    func resultIsSortedBySortOrder() {
        let presets = [makePreset(id: "c", sortOrder: 2), originalPreset(sortOrder: 0), makePreset(id: "b", sortOrder: 1)]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.validPresets.map(\.id) == [PresetDefinition.originalId, "b", "c"])
    }

    @Test
    func missingOriginalIsReported() {
        let presets = [makePreset(id: "warm-memory")]
        let result = PresetValidator.validate(presets, lutResourceExists: { _ in true })
        #expect(result.isMissingOriginal)
    }
}
