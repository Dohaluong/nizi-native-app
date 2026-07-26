//
//  PresetDefinition.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// A complete preset configuration — never just a LUT (docs/modules/photo-editor/ADDEDUM.md § 1,
/// § 2). Defined entirely outside the UI and loaded through `PresetRepository`, so swapping a LUT
/// or retuning texture strength never touches `PhotoEditorView` or `PhotoRenderEngine`.
///
/// Not every preset uses every field — a light preset may only ever set `lutResource` +
/// `contrastOffset`; a film preset adds grain and vignette on top (ADDEDUM § 2).
struct PresetDefinition: Codable, Identifiable, Equatable, Sendable {
    let id: String
    /// Vietnamese fallback text (used if `nameKey`/`shortNameKey` has no catalog entry) — the
    /// actual displayed string always goes through `localizedString(dynamicKey:defaultValue:)`
    /// with `nameKey`/`shortNameKey`, the same `AlbumPageLayout.nameKey` pattern this project
    /// already uses for other JSON-defined, user-facing content (docs/ALBUM_LAYOUT_SYSTEM.md §
    /// Localization) — a bundled JSON resource's text still has to honor the app's EN/VI catalog,
    /// same as any other user-facing string (docs/architecture/ARCHITECTURE.md § 5).
    let name: String
    let shortName: String
    let nameKey: String
    let shortNameKey: String

    /// A bundled `.cube` file name (e.g. `"warm-memory.cube"`), or `nil` for a preset built purely
    /// from Core Image tone adjustments. `nil` for every V1 preset — see `isPrototype`.
    let lutResource: String?
    let lutDimension: Int?

    let defaultIntensity: Float

    let exposureOffset: Float
    let contrastOffset: Float
    let saturationOffset: Float
    let warmthOffset: Float
    let highlightsOffset: Float
    let shadowsOffset: Float

    let grainAmount: Float
    let grainSize: Float
    let bloomAmount: Float
    let bloomRadius: Float
    let vignetteAmount: Float
    let vignetteRadius: Float

    /// Schema-only in V1 — real per-region skin-tone protection is masked/HSL-aware processing,
    /// explicitly out of scope for this app's Photo Editor (see ADDEDUM § 12–14 and
    /// docs/modules/PHOTO-EDITOR-PRESET-GUIDE.md). Parsed and carried through, never acted on by
    /// `PresetRenderer` yet.
    let protectSkinTones: Bool
    let isMonochrome: Bool

    let thumbnailAssetName: String?
    let sortOrder: Int
    let isActive: Bool

    /// ADDEDUM § 5 / § 14.10 requires marking prototype presets (built from Core Image
    /// adjustments, no licensed LUT embedded yet) "clearly in code and docs" until a real `.cube`
    /// replaces them — named `isPrototype` to match this struct's other `is`-prefixed booleans,
    /// rather than the doc's own `prototypePreset` spelling.
    let isPrototype: Bool

    static let originalId = "original"

    var isOriginal: Bool { id == Self.originalId }
}
