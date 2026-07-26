//
//  BundledLUTPresetsTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

/// Confirms every preset in the real bundled `presets.json` that declares a `lutResource` actually
/// has a matching `.cube` file in the bundle, and that `CubeLUTLoader` parses it into the exact
/// dimension the preset claims — catches a filename typo or dimension mismatch directly, the same
/// way `BundlePresetRepositoryTests` catches a broken catalog.
struct BundledLUTPresetsTests {
    @Test
    func everyPresetWithALUTResourceLoadsAndParsesAtItsDeclaredDimension() throws {
        let presets = try BundlePresetRepository().loadPresets()
        let lutPresets = presets.filter { $0.lutResource != nil }
        #expect(!lutPresets.isEmpty, "expected at least one real-LUT preset to be bundled")

        let loader = CubeLUTLoader()
        for preset in lutPresets {
            guard let resource = preset.lutResource, let dimension = preset.lutDimension else {
                Issue.record("preset \(preset.id) has a lutResource but no lutDimension")
                continue
            }
            let cube = try loader.loadCube(resourceName: resource, dimension: dimension)
            #expect(cube.dimension == dimension, "preset \(preset.id) parsed at the wrong dimension")
            #expect(cube.data.count == dimension * dimension * dimension * 4 * MemoryLayout<Float>.size)
        }
    }

    @Test
    func bundledLUTPresetsAreNotFlaggedAsPrototype() throws {
        // These are real, licensed LUTs (not the Core-Image-only prototypes from earlier sprints)
        // — `isPrototype` should reflect that so PHOTO-EDITOR-PRESET-GUIDE.md's bookkeeping stays
        // accurate.
        let presets = try BundlePresetRepository().loadPresets()
        for preset in presets where preset.lutResource != nil {
            #expect(!preset.isPrototype, "preset \(preset.id) has a real LUT but is still marked isPrototype")
        }
    }

    @Test
    func expectedLUTPresetCountIsThirteenPlusOriginal() throws {
        let presets = try BundlePresetRepository().loadPresets()
        #expect(presets.count == 14)
        #expect(presets.filter { $0.lutResource != nil }.count == 13)
    }
}
