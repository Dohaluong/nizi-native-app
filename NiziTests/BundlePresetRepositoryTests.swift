//
//  BundlePresetRepositoryTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

/// Exercises the real bundled `presets.json` through `BundlePresetRepository` — not a synthetic
/// fixture — matching `AlbumLayoutDecodingTests`'s own approach for `album-layouts.json`. This is
/// what actually catches a malformed shipped catalog, not just a hypothetical one.
struct BundlePresetRepositoryTests {
    private func makeRepository() -> BundlePresetRepository {
        BundlePresetRepository()
    }

    @Test
    func loadsUnderTenPresets() throws {
        let presets = try makeRepository().loadPresets()
        #expect(!presets.isEmpty)
        #expect(presets.count < 10)
    }

    @Test
    func includesOriginalWithZeroIntensity() throws {
        let presets = try makeRepository().loadPresets()
        let original = presets.first { $0.isOriginal }
        #expect(original != nil)
        #expect(original?.defaultIntensity == 0)
    }

    @Test
    func everyIdIsUnique() throws {
        let presets = try makeRepository().loadPresets()
        #expect(Set(presets.map(\.id)).count == presets.count)
    }

    @Test
    func isSortedBySortOrder() throws {
        let presets = try makeRepository().loadPresets()
        #expect(presets.map(\.sortOrder) == presets.map(\.sortOrder).sorted())
    }

    @Test
    func everyDefaultIntensityIsInRange() throws {
        let presets = try makeRepository().loadPresets()
        for preset in presets {
            #expect((0...1).contains(preset.defaultIntensity), "preset \(preset.id) has out-of-range defaultIntensity")
        }
    }

    @Test
    func secondLoadReturnsTheSameCachedResultWithoutReDecoding() throws {
        let repository = makeRepository()
        let first = try repository.loadPresets()
        let second = try repository.loadPresets()
        #expect(first == second)
    }

    @Test
    func presetLookupByIdWorks() throws {
        let repository = makeRepository()
        let all = try repository.loadPresets()
        guard let anyPreset = all.first else {
            Issue.record("presets.json shipped with no presets at all")
            return
        }
        #expect(repository.preset(id: anyPreset.id) == anyPreset)
        #expect(repository.preset(id: "not-a-real-preset-id") == nil)
    }
}
