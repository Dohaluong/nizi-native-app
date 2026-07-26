//
//  CustomizablePresetRepositoryTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData
import Testing
@testable import Nizi

private struct FakeBundlePresetRepository: PresetRepository {
    let presets: [PresetDefinition]
    func loadPresets() throws -> [PresetDefinition] { presets }
    func preset(id: String) -> PresetDefinition? { presets.first { $0.id == id } }
}

private final class FakeLUTFileStore: CustomLUTFileStoring, @unchecked Sendable {
    private(set) var storedCount = 0
    private(set) var removedFilenames: [String] = []

    func store(fileURL: URL) throws -> String {
        storedCount += 1
        return "fake-\(storedCount).cube"
    }

    func remove(filename: String) throws {
        removedFilenames.append(filename)
    }
}

struct CustomizablePresetRepositoryTests {
    private func makePreset(id: String, sortOrder: Int) -> PresetDefinition {
        PresetDefinition(
            id: id, name: id, shortName: id, nameKey: "key.\(id).name", shortNameKey: "key.\(id).shortName",
            lutResource: "\(id).cube", lutDimension: 32, defaultIntensity: 0.85,
            exposureOffset: 0, contrastOffset: 0, saturationOffset: 0, warmthOffset: 0,
            highlightsOffset: 0, shadowsOffset: 0, grainAmount: 0, grainSize: 0, bloomAmount: 0,
            bloomRadius: 0, vignetteAmount: 0, vignetteRadius: 0,
            protectSkinTones: true, isMonochrome: false, thumbnailAssetName: nil,
            sortOrder: sortOrder, isActive: true, isPrototype: false
        )
    }

    private func makeRepository(
        bundled: [PresetDefinition],
        lutFileStore: CustomLUTFileStoring = FakeLUTFileStore()
    ) throws -> CustomizablePresetRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MDPresetOverride.self, MDCustomPreset.self, configurations: configuration)
        return CustomizablePresetRepository(
            modelContainer: container,
            bundleRepository: FakeBundlePresetRepository(presets: bundled),
            lutFileStore: lutFileStore
        )
    }

    private func writeTempCubeFile() throws -> URL {
        let text = """
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        0.1 0.1 0.1
        0.2 0.2 0.2
        0.3 0.3 0.3
        0.4 0.4 0.4
        0.5 0.5 0.5
        0.6 0.6 0.6
        0.7 0.7 0.7
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cube")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test
    func withNoOverridesLoadPresetsMatchesBundled() throws {
        let bundled = [makePreset(id: "original", sortOrder: 0), makePreset(id: "brooklyn", sortOrder: 1)]
        let repository = try makeRepository(bundled: bundled)
        let loaded = try repository.loadPresets()
        #expect(loaded.map(\.id) == ["original", "brooklyn"])
    }

    @Test
    func deactivatingABundledPresetHidesItFromLoadPresetsButNotAllPresets() async throws {
        let bundled = [makePreset(id: "original", sortOrder: 0), makePreset(id: "brooklyn", sortOrder: 1)]
        let repository = try makeRepository(bundled: bundled)

        try await repository.setActive(false, presetId: "brooklyn")

        let loaded = try repository.loadPresets()
        #expect(!loaded.contains { $0.id == "brooklyn" })

        let all = try await repository.allPresets()
        let brooklyn = all.first { $0.id == "brooklyn" }
        #expect(brooklyn != nil)
        #expect(brooklyn?.isActive == false)
    }

    @Test
    func renamingABundledPresetOverridesDisplayNameOnly() async throws {
        let bundled = [makePreset(id: "original", sortOrder: 0), makePreset(id: "brooklyn", sortOrder: 1)]
        let repository = try makeRepository(bundled: bundled)

        try await repository.rename(presetId: "brooklyn", name: "My Brooklyn", shortName: "MyBK")

        let loaded = try repository.loadPresets()
        let renamed = loaded.first { $0.id == "brooklyn" }
        #expect(renamed?.name == "My Brooklyn")
        #expect(renamed?.shortName == "MyBK")
        #expect(renamed?.lutResource == "brooklyn.cube") // everything else about the bundled preset is untouched
    }

    @Test
    func isBundledPresetDistinguishesBundledFromCustom() throws {
        let bundled = [makePreset(id: "original", sortOrder: 0)]
        let repository = try makeRepository(bundled: bundled)
        #expect(repository.isBundledPreset(id: "original"))
        #expect(!repository.isBundledPreset(id: "custom-abc"))
    }

    @Test
    func addingACustomPresetMakesItAppearInLoadPresets() async throws {
        let bundled = [makePreset(id: "original", sortOrder: 0)]
        let fileStore = FakeLUTFileStore()
        let repository = try makeRepository(bundled: bundled, lutFileStore: fileStore)
        let fileURL = try writeTempCubeFile()

        let added = try await repository.addCustomPreset(fileURL: fileURL, name: "My LUT", shortName: "MyLUT", defaultIntensity: 0.9)

        #expect(!repository.isBundledPreset(id: added.id))
        #expect(fileStore.storedCount == 1)

        let loaded = try repository.loadPresets()
        #expect(loaded.contains { $0.id == added.id })
        #expect(loaded.first { $0.id == added.id }?.name == "My LUT")
    }

    @Test
    func addingAnInvalidCubeFileThrows() async throws {
        let bundled = [makePreset(id: "original", sortOrder: 0)]
        let repository = try makeRepository(bundled: bundled)
        let badURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cube")
        try "not a real cube file".write(to: badURL, atomically: true, encoding: .utf8)

        await #expect(throws: PresetManagingError.invalidLUTFile) {
            try await repository.addCustomPreset(fileURL: badURL, name: "Bad", shortName: "Bad", defaultIntensity: 0.85)
        }
    }

    @Test
    func removingACustomPresetDeletesItAndItsFile() async throws {
        let bundled = [makePreset(id: "original", sortOrder: 0)]
        let fileStore = FakeLUTFileStore()
        let repository = try makeRepository(bundled: bundled, lutFileStore: fileStore)
        let fileURL = try writeTempCubeFile()
        let added = try await repository.addCustomPreset(fileURL: fileURL, name: "My LUT", shortName: "MyLUT", defaultIntensity: 0.9)

        try await repository.removeCustomPreset(id: added.id)

        let loaded = try repository.loadPresets()
        #expect(!loaded.contains { $0.id == added.id })
        #expect(fileStore.removedFilenames.count == 1)
    }

    @Test
    func removingABundledPresetThrows() async throws {
        let bundled = [makePreset(id: "original", sortOrder: 0)]
        let repository = try makeRepository(bundled: bundled)

        await #expect(throws: PresetManagingError.cannotDeleteBundledPreset) {
            try await repository.removeCustomPreset(id: "original")
        }
    }
}
