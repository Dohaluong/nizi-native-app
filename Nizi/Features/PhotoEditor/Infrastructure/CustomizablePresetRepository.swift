//
//  CustomizablePresetRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData

/// The one `PresetRepository` every real call site (Album, Event, standalone) should construct —
/// merges the bundled `presets.json` catalog with the user's own active/name overrides and
/// imported custom presets. A plain lock-protected class, not an `@ModelActor` actor, so it can
/// keep satisfying `PresetRepository`'s existing *synchronous* `loadPresets()`/`preset(id:)` —
/// changing that protocol to `async` would cascade through `PhotoRenderEngine` and every render
/// call site for a feature (LUT management) only the new management screen needs. `PresetManaging`
/// (this type's other conformance) is `async` freely, since nothing existing depends on it.
final class CustomizablePresetRepository: PresetRepository, PresetManaging, @unchecked Sendable {
    private let lock = NSLock()
    private let modelContext: ModelContext
    private let bundleRepository: PresetRepository
    private let lutFileStore: CustomLUTFileStoring
    private var cachedPresets: [PresetDefinition]?

    init(
        modelContainer: ModelContainer,
        bundleRepository: PresetRepository = BundlePresetRepository(),
        lutFileStore: CustomLUTFileStoring = DocumentsCustomLUTFileStore()
    ) {
        modelContext = ModelContext(modelContainer)
        self.bundleRepository = bundleRepository
        self.lutFileStore = lutFileStore
    }

    // MARK: - PresetRepository

    func loadPresets() throws -> [PresetDefinition] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPresets { return cachedPresets }
        let result = try computeEffectivePresets()
        cachedPresets = result
        return result
    }

    func preset(id: String) -> PresetDefinition? {
        (try? loadPresets())?.first { $0.id == id }
    }

    // MARK: - PresetManaging

    func allPresets() async throws -> [PresetDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return try mergedPresets(filterActive: false)
    }

    func isBundledPreset(id: String) -> Bool {
        ((try? bundleRepository.loadPresets()) ?? []).contains { $0.id == id }
    }

    func setActive(_ isActive: Bool, presetId: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        if isBundledPreset(id: presetId) {
            try upsertOverride(presetId: presetId) { $0.isActive = isActive }
        } else {
            try updateCustomPreset(id: presetId) { $0.isActive = isActive }
        }
        cachedPresets = nil
    }

    func rename(presetId: String, name: String, shortName: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        if isBundledPreset(id: presetId) {
            try upsertOverride(presetId: presetId) {
                $0.nameOverride = name
                $0.shortNameOverride = shortName
            }
        } else {
            try updateCustomPreset(id: presetId) {
                $0.name = name
                $0.shortName = shortName
            }
        }
        cachedPresets = nil
    }

    func addCustomPreset(fileURL: URL, name: String, shortName: String, defaultIntensity: Float) async throws -> PresetDefinition {
        // Validate the file *before* copying/persisting anything durable — a bad file must never
        // leave a half-created preset or an orphaned copied .cube behind.
        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw PresetManagingError.invalidLUTFile
        }
        guard let dimension = CubeFileParser.declaredDimension(in: text) else {
            throw PresetManagingError.invalidLUTFile
        }
        guard (try? CubeFileParser.parse(text: text, expectedDimension: dimension)) != nil else {
            throw PresetManagingError.invalidLUTFile
        }

        let filename = try lutFileStore.store(fileURL: fileURL)
        let id = "custom-\(UUID().uuidString)"

        lock.lock()
        let sortOrder = try nextCustomSortOrder()
        lock.unlock()

        let preset = PresetDefinition(
            id: id,
            name: name,
            shortName: shortName,
            // Custom presets are user-generated content, not shipped catalog content — no real
            // catalog key exists for them, so `nameKey`/`shortNameKey` intentionally point at a
            // key that will never resolve; `localizedString(dynamicKey:defaultValue:)` falls back
            // to `name`/`shortName` verbatim in that case, which is exactly what's wanted here.
            nameKey: "photoEditor.preset.custom.\(id).name",
            shortNameKey: "photoEditor.preset.custom.\(id).shortName",
            lutResource: filename,
            lutDimension: dimension,
            defaultIntensity: min(max(defaultIntensity, 0), 1),
            exposureOffset: 0, contrastOffset: 0, saturationOffset: 0, warmthOffset: 0,
            highlightsOffset: 0, shadowsOffset: 0,
            grainAmount: 0, grainSize: 0, bloomAmount: 0, bloomRadius: 0,
            vignetteAmount: 0, vignetteRadius: 0,
            protectSkinTones: true, isMonochrome: false,
            thumbnailAssetName: nil, sortOrder: sortOrder, isActive: true, isPrototype: false
        )

        lock.lock()
        defer { lock.unlock() }
        modelContext.insert(try MDCustomPreset(preset: preset, createdAt: Date()))
        try modelContext.save()
        cachedPresets = nil
        return preset
    }

    func saveCustomPreset(_ preset: PresetDefinition) async throws -> PresetDefinition {
        lock.lock()
        defer { lock.unlock() }

        let bundledIds = Set(((try? bundleRepository.loadPresets()) ?? []).map(\.id))
        let customIds = Set((try fetchCustomPresets()).map(\.id))
        guard !bundledIds.contains(preset.id), !customIds.contains(preset.id) else {
            throw PresetManagingError.duplicateId
        }

        var saved = preset
        saved.sortOrder = try nextCustomSortOrder()
        saved.isActive = true

        modelContext.insert(try MDCustomPreset(preset: saved, createdAt: Date()))
        try modelContext.save()
        cachedPresets = nil
        return saved
    }

    func removeCustomPreset(id: String) async throws {
        guard !isBundledPreset(id: id) else { throw PresetManagingError.cannotDeleteBundledPreset }

        lock.lock()
        defer { lock.unlock() }
        var descriptor = FetchDescriptor<MDCustomPreset>(predicate: #Predicate { $0.presetId == id })
        descriptor.fetchLimit = 1
        guard let existing = try modelContext.fetch(descriptor).first else {
            throw PresetManagingError.presetNotFound
        }
        let preset = try existing.decodedPreset()
        modelContext.delete(existing)
        try modelContext.save()
        if let lutResource = preset.lutResource {
            try? lutFileStore.remove(filename: lutResource)
        }
        cachedPresets = nil
    }

    // MARK: - Private

    /// `PresetRepository.loadPresets()` (used by the editor's own Preset strip) always wants
    /// `filterActive: true`; `PresetManaging.allPresets()` (the management screen) wants `false`
    /// so a deactivated preset is still listed and can be re-activated. Not locked itself — every
    /// call site already holds `lock`.
    private func mergedPresets(filterActive: Bool) throws -> [PresetDefinition] {
        let bundled = try bundleRepository.loadPresets()
        let overridesByPresetId = try fetchOverrides()

        let customizedBundled = bundled.map { preset -> PresetDefinition in
            guard let override = overridesByPresetId[preset.id] else { return preset }
            var updated = preset
            updated.isActive = override.isActive
            if let name = override.nameOverride { updated.name = name }
            if let shortName = override.shortNameOverride { updated.shortName = shortName }
            return updated
        }

        let custom = try fetchCustomPresets()
        let all = customizedBundled + custom
        return (filterActive ? all.filter(\.isActive) : all)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func computeEffectivePresets() throws -> [PresetDefinition] {
        try mergedPresets(filterActive: true)
    }

    private func fetchOverrides() throws -> [String: MDPresetOverride] {
        let all = try modelContext.fetch(FetchDescriptor<MDPresetOverride>())
        return Dictionary(uniqueKeysWithValues: all.map { ($0.presetId, $0) })
    }

    private func fetchCustomPresets() throws -> [PresetDefinition] {
        let all = try modelContext.fetch(FetchDescriptor<MDCustomPreset>(sortBy: [SortDescriptor(\.createdAt)]))
        return try all.map { try $0.decodedPreset() }
    }

    private func nextCustomSortOrder() throws -> Int {
        let bundledMax = ((try? bundleRepository.loadPresets()) ?? []).map(\.sortOrder).max() ?? 0
        let customCount = (try? fetchCustomPresets().count) ?? 0
        return bundledMax + 1 + customCount
    }

    /// Not locked itself — every call site already holds `lock` before calling this.
    private func upsertOverride(presetId: String, mutate: (MDPresetOverride) -> Void) throws {
        var descriptor = FetchDescriptor<MDPresetOverride>(predicate: #Predicate { $0.presetId == presetId })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            mutate(existing)
            existing.updatedAt = Date()
        } else {
            let newOverride = MDPresetOverride(
                presetId: presetId,
                isActive: bundleRepository.preset(id: presetId)?.isActive ?? true,
                nameOverride: nil,
                shortNameOverride: nil,
                updatedAt: Date()
            )
            mutate(newOverride)
            modelContext.insert(newOverride)
        }
        try modelContext.save()
    }

    /// Not locked itself — every call site already holds `lock` before calling this.
    private func updateCustomPreset(id: String, mutate: (inout PresetDefinition) -> Void) throws {
        var descriptor = FetchDescriptor<MDCustomPreset>(predicate: #Predicate { $0.presetId == id })
        descriptor.fetchLimit = 1
        guard let existing = try modelContext.fetch(descriptor).first else {
            throw PresetManagingError.presetNotFound
        }
        var preset = try existing.decodedPreset()
        mutate(&preset)
        try existing.updateEncodedPreset(preset)
        try modelContext.save()
    }
}
