//
//  PresetManaging.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// CRUD for a LUT/preset management screen — layered on top of `PresetRepository`'s read-only
/// `loadPresets()`/`preset(id:)` (which is all `PhotoRenderEngine`/`PhotoEditorViewModel` ever use).
/// A bundled preset (shipped in `presets.json`) can only have its active state and display name
/// overridden here — `presets.json` itself is a read-only app-bundle resource an installed app can
/// never rewrite. A custom preset (imported via `addCustomPreset`) supports the full set,
/// including removal.
protocol PresetManaging: Sendable {
    /// Every preset — bundled (with overrides applied) and custom — **including inactive ones**,
    /// unlike `PresetRepository.loadPresets()` (which only ever returns active presets, since
    /// that's all the editor's own Preset strip should show). This is what the management screen
    /// lists, so a deactivated preset can still be found and re-activated.
    func allPresets() async throws -> [PresetDefinition]

    /// `true` if `presetId` ships in `presets.json` (only active/name can be overridden); `false`
    /// if it's a custom preset the user imported (fully removable).
    func isBundledPreset(id: String) -> Bool

    func setActive(_ isActive: Bool, presetId: String) async throws
    func rename(presetId: String, name: String, shortName: String) async throws

    /// Copies `fileURL` into app storage and parses it once (via `CubeFileParser`) to confirm it's
    /// a valid `.cube` before accepting it — never stores an unparseable file. Adds it as a new,
    /// active preset.
    func addCustomPreset(fileURL: URL, name: String, shortName: String, defaultIntensity: Float) async throws -> PresetDefinition

    /// Persists an already-fully-formed `PresetDefinition` as a new custom preset — unlike
    /// `addCustomPreset(fileURL:...)`, this never touches the filesystem: `preset.lutResource` (if
    /// any) is expected to already resolve via `CubeLUTLoader` (a bundled `.cube` name, or a
    /// filename already copied into `DocumentsCustomLUTFileStore`'s directory). Exists for the
    /// DEBUG-only Preset Tuning Panel's "Save as New Preset" — tuning an existing preset's
    /// parameters never introduces a brand-new `.cube` file, only `addCustomPreset` handles that.
    /// `preset.id` must not already exist among bundled or custom presets (throws `.duplicateId`);
    /// `preset.sortOrder`/`preset.isActive` are overwritten (a fresh trailing sort position,
    /// always active) regardless of what the caller passed in.
    func saveCustomPreset(_ preset: PresetDefinition) async throws -> PresetDefinition

    /// Only valid for a custom preset — throws `.cannotDeleteBundledPreset` for a bundled one.
    /// Removes both the catalog row and its copied `.cube` file.
    func removeCustomPreset(id: String) async throws
}

enum PresetManagingError: Error, Equatable {
    case cannotDeleteBundledPreset
    case invalidLUTFile
    case presetNotFound
    case duplicateId
}
