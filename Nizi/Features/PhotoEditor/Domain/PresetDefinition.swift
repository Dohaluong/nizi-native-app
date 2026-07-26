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
    /// `var`, not `let` — `PresetManaging` implementations rename a bundled preset by producing a
    /// copy with these overridden, not by mutating `presets.json` (which is a read-only bundle
    /// resource an installed app can never rewrite).
    var name: String
    var shortName: String
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
    /// Diagnostics-only additions (Preset Tuning Panel) — absent from every preset shipped before
    /// that tool existed, so decoding must tolerate a missing key (see `init(from:)` below) rather
    /// than fail every bundled preset the moment one new field is introduced.
    let blacksOffset: Float
    let whitesOffset: Float
    /// Applied *in addition to* `saturationOffset` (`PhotoToneAdjuster`), not a replacement for
    /// it — `CIVibrance` boosts muted colors more than already-saturated ones and is more
    /// skin-tone-safe, which is why the Preset Tuning Panel's Color section leads with this over
    /// plain Saturation, but both still exist as independent, addable offsets.
    let vibranceOffset: Float
    /// Green↔Magenta axis of the same `CITemperatureAndTint` filter `warmthOffset` already drives
    /// (its `neutral`/`targetNeutral` vectors are `(temperature, tint)` pairs) — `PhotoToneAdjuster`
    /// sets both from one filter invocation.
    let tintOffset: Float

    let grainAmount: Float
    let grainSize: Float
    let bloomAmount: Float
    let bloomRadius: Float
    let vignetteAmount: Float
    let vignetteRadius: Float
    /// `CISharpenLuminance`'s `sharpness`, applied in `PresetRenderer`'s texture stage alongside
    /// grain/bloom/vignette.
    let sharpnessAmount: Float
    /// TODO — no local-contrast/"clarity" engine exists yet (Preset Tuning Panel spec explicitly
    /// allows shipping the schema field + UI slider ahead of the actual Core Image implementation).
    /// Parsed and carried through, never acted on by `PresetRenderer` yet — same status
    /// `protectSkinTones` already has below.
    let clarityOffset: Float

    /// Schema-only in V1 — real per-region skin-tone protection is masked/HSL-aware processing,
    /// explicitly out of scope for this app's Photo Editor (see ADDEDUM § 12–14 and
    /// docs/modules/PHOTO-EDITOR-PRESET-GUIDE.md). Parsed and carried through, never acted on by
    /// `PresetRenderer` yet.
    let protectSkinTones: Bool
    let isMonochrome: Bool

    let thumbnailAssetName: String?
    /// `var` — `PresetManaging.saveCustomPreset` assigns a fresh trailing `sortOrder` to a
    /// Preset Tuning Panel-authored preset before persisting it, same mutability reasoning as
    /// `isActive` below.
    var sortOrder: Int
    /// `var` for the same reason `name`/`shortName` are — `PresetManaging` toggles this via an
    /// override row, never by rewriting `presets.json`.
    var isActive: Bool

    /// ADDEDUM § 5 / § 14.10 requires marking prototype presets (built from Core Image
    /// adjustments, no licensed LUT embedded yet) "clearly in code and docs" until a real `.cube`
    /// replaces them — named `isPrototype` to match this struct's other `is`-prefixed booleans,
    /// rather than the doc's own `prototypePreset` spelling.
    let isPrototype: Bool

    static let originalId = "original"

    var isOriginal: Bool { id == Self.originalId }

    init(
        id: String, name: String, shortName: String, nameKey: String, shortNameKey: String,
        lutResource: String?, lutDimension: Int?, defaultIntensity: Float,
        exposureOffset: Float, contrastOffset: Float, saturationOffset: Float, warmthOffset: Float,
        highlightsOffset: Float, shadowsOffset: Float,
        blacksOffset: Float = 0, whitesOffset: Float = 0, vibranceOffset: Float = 0, tintOffset: Float = 0,
        grainAmount: Float, grainSize: Float, bloomAmount: Float, bloomRadius: Float,
        vignetteAmount: Float, vignetteRadius: Float, sharpnessAmount: Float = 0, clarityOffset: Float = 0,
        protectSkinTones: Bool, isMonochrome: Bool,
        thumbnailAssetName: String?, sortOrder: Int, isActive: Bool, isPrototype: Bool
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.nameKey = nameKey
        self.shortNameKey = shortNameKey
        self.lutResource = lutResource
        self.lutDimension = lutDimension
        self.defaultIntensity = defaultIntensity
        self.exposureOffset = exposureOffset
        self.contrastOffset = contrastOffset
        self.saturationOffset = saturationOffset
        self.warmthOffset = warmthOffset
        self.highlightsOffset = highlightsOffset
        self.shadowsOffset = shadowsOffset
        self.blacksOffset = blacksOffset
        self.whitesOffset = whitesOffset
        self.vibranceOffset = vibranceOffset
        self.tintOffset = tintOffset
        self.grainAmount = grainAmount
        self.grainSize = grainSize
        self.bloomAmount = bloomAmount
        self.bloomRadius = bloomRadius
        self.vignetteAmount = vignetteAmount
        self.vignetteRadius = vignetteRadius
        self.sharpnessAmount = sharpnessAmount
        self.clarityOffset = clarityOffset
        self.protectSkinTones = protectSkinTones
        self.isMonochrome = isMonochrome
        self.thumbnailAssetName = thumbnailAssetName
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.isPrototype = isPrototype
    }

    /// Hand-written instead of synthesized so the six Preset Tuning Panel fields
    /// (`blacksOffset`/`whitesOffset`/`vibranceOffset`/`tintOffset`/`sharpnessAmount`/
    /// `clarityOffset`) can default to `0` when absent — every preset shipped before the tuning
    /// panel existed lacks these keys entirely, and a plain synthesized `Decodable` would throw
    /// `keyNotFound` for every one of them the moment a single new field was added. `encode(to:)`
    /// stays synthesized (unaffected by providing just `init(from:)` here).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        shortName = try container.decode(String.self, forKey: .shortName)
        nameKey = try container.decode(String.self, forKey: .nameKey)
        shortNameKey = try container.decode(String.self, forKey: .shortNameKey)
        lutResource = try container.decodeIfPresent(String.self, forKey: .lutResource)
        lutDimension = try container.decodeIfPresent(Int.self, forKey: .lutDimension)
        defaultIntensity = try container.decode(Float.self, forKey: .defaultIntensity)
        exposureOffset = try container.decode(Float.self, forKey: .exposureOffset)
        contrastOffset = try container.decode(Float.self, forKey: .contrastOffset)
        saturationOffset = try container.decode(Float.self, forKey: .saturationOffset)
        warmthOffset = try container.decode(Float.self, forKey: .warmthOffset)
        highlightsOffset = try container.decode(Float.self, forKey: .highlightsOffset)
        shadowsOffset = try container.decode(Float.self, forKey: .shadowsOffset)
        blacksOffset = try container.decodeIfPresent(Float.self, forKey: .blacksOffset) ?? 0
        whitesOffset = try container.decodeIfPresent(Float.self, forKey: .whitesOffset) ?? 0
        vibranceOffset = try container.decodeIfPresent(Float.self, forKey: .vibranceOffset) ?? 0
        tintOffset = try container.decodeIfPresent(Float.self, forKey: .tintOffset) ?? 0
        grainAmount = try container.decode(Float.self, forKey: .grainAmount)
        grainSize = try container.decode(Float.self, forKey: .grainSize)
        bloomAmount = try container.decode(Float.self, forKey: .bloomAmount)
        bloomRadius = try container.decode(Float.self, forKey: .bloomRadius)
        vignetteAmount = try container.decode(Float.self, forKey: .vignetteAmount)
        vignetteRadius = try container.decode(Float.self, forKey: .vignetteRadius)
        sharpnessAmount = try container.decodeIfPresent(Float.self, forKey: .sharpnessAmount) ?? 0
        clarityOffset = try container.decodeIfPresent(Float.self, forKey: .clarityOffset) ?? 0
        protectSkinTones = try container.decode(Bool.self, forKey: .protectSkinTones)
        isMonochrome = try container.decode(Bool.self, forKey: .isMonochrome)
        thumbnailAssetName = try container.decodeIfPresent(String.self, forKey: .thumbnailAssetName)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isPrototype = try container.decode(Bool.self, forKey: .isPrototype)
    }
}
