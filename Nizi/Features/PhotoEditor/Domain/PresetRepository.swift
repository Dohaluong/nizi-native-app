//
//  PresetRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Loads and looks up presets — never touches Core Image or PHAsset (ADDEDUM.md § 6:
/// "Repository... Đọc và ghi... Không xử lý hình ảnh").
protocol PresetRepository: Sendable {
    /// Every valid, active preset, sorted by `sortOrder`. Implementations must cache after the
    /// first successful load (ADDEDUM § 6/§ 15 — "LUT chỉ parse một lần" applies just as much to
    /// not re-decoding/re-validating `presets.json` on every call).
    func loadPresets() throws -> [PresetDefinition]
    func preset(id: String) -> PresetDefinition?
}

enum PresetRepositoryError: Error, Equatable {
    case resourceMissing
    case decodingFailed(String)
}
