//
//  BundlePresetRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Production `PresetRepository` — reads `presets.json` from the app bundle, decodes it, filters
/// it through `PresetValidator`, and caches the result (never re-decoded/re-validated after the
/// first successful load). Mirrors `BundleAlbumLayoutRepository`'s exact shape (same bundle-JSON,
/// injectable-`Bundle`, cache-after-first-load pattern) — this project's established convention
/// for "definitions loaded from a bundled JSON resource."
final class BundlePresetRepository: PresetRepository, @unchecked Sendable {
    private let bundle: Bundle
    private let resourceName: String
    private let lock = NSLock()
    private var cachedPresets: [PresetDefinition]?

    init(bundle: Bundle = .main, resourceName: String = "presets") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func loadPresets() throws -> [PresetDefinition] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPresets { return cachedPresets }

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw PresetRepositoryError.resourceMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PresetRepositoryError.resourceMissing
        }

        let decoded: [PresetDefinition]
        do {
            decoded = try JSONDecoder().decode([PresetDefinition].self, from: data)
        } catch {
            throw PresetRepositoryError.decodingFailed(String(describing: error))
        }

        let result = PresetValidator.validate(decoded) { [bundle] lutResource in
            let name = (lutResource as NSString).deletingPathExtension
            let ext = (lutResource as NSString).pathExtension
            return bundle.url(forResource: name, withExtension: ext.isEmpty ? "cube" : ext) != nil
        }

        for skipped in result.skipped {
            NiziLogger.photoEditor.error("preset_skipped id=\(skipped.id, privacy: .public) reason=\(skipped.reason, privacy: .public)")
        }
        if result.isMissingOriginal {
            NiziLogger.photoEditor.error("preset_catalog_missing_original")
        }

        cachedPresets = result.validPresets
        return result.validPresets
    }

    func preset(id: String) -> PresetDefinition? {
        (try? loadPresets())?.first { $0.id == id }
    }
}
