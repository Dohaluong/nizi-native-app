//
//  PresetValidator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Validates a decoded preset catalog against docs/modules/photo-editor/ADDEDUM.md § 6's minimum
/// rules. A single malformed preset must never crash the app or block the rest of the catalog —
/// this drops the offending entry and reports why, so `BundlePresetRepository` can log it and keep
/// going (§ 6: "Nếu một preset lỗi: Không làm crash app. Ghi log. Bỏ qua preset lỗi."). Pure/no
/// framework imports — logging the skipped reasons is Infrastructure's job, not Domain's (this
/// codebase's other Domain layers never call `NiziLogger` either).
enum PresetValidator {
    struct SkippedPreset: Equatable {
        let id: String
        let reason: String
    }

    struct Result: Equatable {
        let validPresets: [PresetDefinition]
        let skipped: [SkippedPreset]
        var isMissingOriginal: Bool { !validPresets.contains { $0.isOriginal } }
    }

    /// - Parameter lutResourceExists: Injected rather than touching `Bundle` directly, so this
    ///   stays testable with plain in-memory presets and no app bundle.
    static func validate(_ presets: [PresetDefinition], lutResourceExists: (String) -> Bool) -> Result {
        var seenIds = Set<String>()
        var valid: [PresetDefinition] = []
        var skipped: [SkippedPreset] = []

        for preset in presets where preset.isActive {
            guard seenIds.insert(preset.id).inserted else {
                skipped.append(SkippedPreset(id: preset.id, reason: "duplicate id"))
                continue
            }
            guard (0...1).contains(preset.defaultIntensity) else {
                skipped.append(SkippedPreset(id: preset.id, reason: "defaultIntensity out of 0...1"))
                continue
            }
            guard preset.grainAmount >= 0, preset.bloomAmount >= 0, preset.vignetteAmount >= 0,
                  preset.grainSize >= 0, preset.bloomRadius >= 0, preset.vignetteRadius >= 0
            else {
                skipped.append(SkippedPreset(id: preset.id, reason: "negative effect amount or radius"))
                continue
            }
            if let lutResource = preset.lutResource {
                guard let dimension = preset.lutDimension, dimension > 0 else {
                    skipped.append(SkippedPreset(id: preset.id, reason: "lutResource set without a valid lutDimension"))
                    continue
                }
                guard lutResourceExists(lutResource) else {
                    skipped.append(SkippedPreset(id: preset.id, reason: "lutResource not found in bundle"))
                    continue
                }
            }
            if preset.isOriginal, preset.defaultIntensity != 0 {
                skipped.append(SkippedPreset(id: preset.id, reason: "Original preset must have defaultIntensity 0"))
                continue
            }

            valid.append(preset)
        }

        let sorted = valid.sorted { $0.sortOrder < $1.sortOrder }
        return Result(validPresets: sorted, skipped: skipped)
    }
}
