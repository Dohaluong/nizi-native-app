//
//  PresetTuningJSON.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// One `HSLColorBand`'s own Hue/Saturation/Lightness, in the same *display* units
/// `HSLTuningComponent` uses (± degrees / ± percent) — the HSL counterpart to
/// `PresetTuningJSON`'s own top-level fields, nested once per band below.
struct PresetTuningHSLBandJSON: Codable, Equatable {
    var hue: Double = 0
    var saturation: Double = 0
    var lightness: Double = 0
}

/// All 8 bands, named the same as `PresetHSLAdjustments`'s own fields so `presets.json`/pasted
/// JSON both read as a plain `{"red": {...}, "orange": {...}, ...}` object — never a
/// `Dictionary<HSLColorBand, _>`, which Codable would instead round-trip as an alternating
/// key/value array.
struct PresetTuningHSLJSON: Codable, Equatable {
    var red = PresetTuningHSLBandJSON()
    var orange = PresetTuningHSLBandJSON()
    var yellow = PresetTuningHSLBandJSON()
    var green = PresetTuningHSLBandJSON()
    var aqua = PresetTuningHSLBandJSON()
    var blue = PresetTuningHSLBandJSON()
    var purple = PresetTuningHSLBandJSON()
    var magenta = PresetTuningHSLBandJSON()
}

/// The Preset Tuning Panel's "Copy JSON"/"Import JSON" shape — deliberately *not* `PresetDefinition`
/// itself (which carries id/name/nameKey/sortOrder/etc. that a color-grading pass over an existing
/// preset never needs to retype). Every numeric field is in the same *display* units the sliders
/// themselves use (EV for `exposure`, `-100...100`/`0...100` for everything else,
/// `PresetTuningParameter`'s own units) — not the engine's internal `-1...1`/`0...1` storage — so a
/// pasted value reads the same as what the slider showed.
struct PresetTuningJSON: Codable, Equatable {
    var lut: String?
    var defaultIntensity: Double
    var toneCurve: Double
    var exposure: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var whites: Double
    var blacks: Double
    var warmth: Double
    var tint: Double
    var saturation: Double
    var vibrance: Double
    var bloom: Double
    var grain: Double
    var vignette: Double
    var sharpness: Double
    /// Absent from the spec's own example JSON (written before `clarityOffset` existed) —
    /// `decodeIfPresent` so a pasted legacy snippet without this key still imports cleanly.
    var clarity: Double
    /// Absent from every JSON snapshot taken before the HSL tool existed — `decodeIfPresent` with
    /// an all-zero default, same reasoning `clarity`/`toneCurve` above already have.
    var hsl: PresetTuningHSLJSON

    private enum CodingKeys: String, CodingKey {
        case lut, defaultIntensity, toneCurve, exposure, contrast, highlights, shadows, whites, blacks,
             warmth, tint, saturation, vibrance, bloom, grain, vignette, sharpness, clarity, hsl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lut = try container.decodeIfPresent(String.self, forKey: .lut)
        defaultIntensity = try container.decode(Double.self, forKey: .defaultIntensity)
        // Absent from the spec's own example JSON (written before toneCurveAmount existed) —
        // decodeIfPresent so a pasted legacy snippet without this key still imports cleanly.
        toneCurve = try container.decodeIfPresent(Double.self, forKey: .toneCurve) ?? 0
        exposure = try container.decode(Double.self, forKey: .exposure)
        contrast = try container.decode(Double.self, forKey: .contrast)
        highlights = try container.decode(Double.self, forKey: .highlights)
        shadows = try container.decode(Double.self, forKey: .shadows)
        whites = try container.decode(Double.self, forKey: .whites)
        blacks = try container.decode(Double.self, forKey: .blacks)
        warmth = try container.decode(Double.self, forKey: .warmth)
        tint = try container.decode(Double.self, forKey: .tint)
        saturation = try container.decode(Double.self, forKey: .saturation)
        vibrance = try container.decode(Double.self, forKey: .vibrance)
        bloom = try container.decode(Double.self, forKey: .bloom)
        grain = try container.decode(Double.self, forKey: .grain)
        vignette = try container.decode(Double.self, forKey: .vignette)
        sharpness = try container.decode(Double.self, forKey: .sharpness)
        clarity = try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        hsl = try container.decodeIfPresent(PresetTuningHSLJSON.self, forKey: .hsl) ?? PresetTuningHSLJSON()
    }

    init(preset: PresetDefinition) {
        lut = preset.lutResource
        defaultIntensity = Double(preset.defaultIntensity)
        toneCurve = PresetTuningParameter.toneCurve.displayValue(in: preset)
        exposure = PresetTuningParameter.exposure.displayValue(in: preset)
        contrast = PresetTuningParameter.contrast.displayValue(in: preset)
        highlights = PresetTuningParameter.highlights.displayValue(in: preset)
        shadows = PresetTuningParameter.shadows.displayValue(in: preset)
        whites = PresetTuningParameter.whites.displayValue(in: preset)
        blacks = PresetTuningParameter.blacks.displayValue(in: preset)
        warmth = PresetTuningParameter.warmth.displayValue(in: preset)
        tint = PresetTuningParameter.tint.displayValue(in: preset)
        saturation = PresetTuningParameter.saturation.displayValue(in: preset)
        vibrance = PresetTuningParameter.vibrance.displayValue(in: preset)
        bloom = PresetTuningParameter.bloom.displayValue(in: preset)
        grain = PresetTuningParameter.grain.displayValue(in: preset)
        vignette = PresetTuningParameter.vignette.displayValue(in: preset)
        sharpness = PresetTuningParameter.sharpness.displayValue(in: preset)
        clarity = PresetTuningParameter.clarity.displayValue(in: preset)
        hsl = PresetTuningHSLJSON(
            red: Self.jsonBand(preset.hsl.red), orange: Self.jsonBand(preset.hsl.orange),
            yellow: Self.jsonBand(preset.hsl.yellow), green: Self.jsonBand(preset.hsl.green),
            aqua: Self.jsonBand(preset.hsl.aqua), blue: Self.jsonBand(preset.hsl.blue),
            purple: Self.jsonBand(preset.hsl.purple), magenta: Self.jsonBand(preset.hsl.magenta)
        )
    }

    private static func jsonBand(_ adjustment: HSLBandAdjustment) -> PresetTuningHSLBandJSON {
        PresetTuningHSLBandJSON(
            hue: HSLTuningComponent.hue.displayValue(in: adjustment),
            saturation: HSLTuningComponent.saturation.displayValue(in: adjustment),
            lightness: HSLTuningComponent.lightness.displayValue(in: adjustment)
        )
    }

    private static func domainBand(_ json: PresetTuningHSLBandJSON) -> HSLBandAdjustment {
        var adjustment = HSLBandAdjustment()
        HSLTuningComponent.hue.setDisplayValue(json.hue, in: &adjustment)
        HSLTuningComponent.saturation.setDisplayValue(json.saturation, in: &adjustment)
        HSLTuningComponent.lightness.setDisplayValue(json.lightness, in: &adjustment)
        return adjustment
    }

    /// Applies every field onto a copy of `preset` — `id`/`name`/`nameKey`/`sortOrder`/etc. (nothing
    /// this JSON shape carries) pass through untouched.
    func applying(to preset: PresetDefinition) -> PresetDefinition {
        var updated = preset
        updated.lutResource = lut
        updated.defaultIntensity = Float(min(max(defaultIntensity, 0), 1))
        PresetTuningParameter.toneCurve.setDisplayValue(toneCurve, in: &updated)
        PresetTuningParameter.exposure.setDisplayValue(exposure, in: &updated)
        PresetTuningParameter.contrast.setDisplayValue(contrast, in: &updated)
        PresetTuningParameter.highlights.setDisplayValue(highlights, in: &updated)
        PresetTuningParameter.shadows.setDisplayValue(shadows, in: &updated)
        PresetTuningParameter.whites.setDisplayValue(whites, in: &updated)
        PresetTuningParameter.blacks.setDisplayValue(blacks, in: &updated)
        PresetTuningParameter.warmth.setDisplayValue(warmth, in: &updated)
        PresetTuningParameter.tint.setDisplayValue(tint, in: &updated)
        PresetTuningParameter.saturation.setDisplayValue(saturation, in: &updated)
        PresetTuningParameter.vibrance.setDisplayValue(vibrance, in: &updated)
        PresetTuningParameter.bloom.setDisplayValue(bloom, in: &updated)
        PresetTuningParameter.grain.setDisplayValue(grain, in: &updated)
        PresetTuningParameter.vignette.setDisplayValue(vignette, in: &updated)
        PresetTuningParameter.sharpness.setDisplayValue(sharpness, in: &updated)
        PresetTuningParameter.clarity.setDisplayValue(clarity, in: &updated)
        updated.hsl = PresetHSLAdjustments(
            red: Self.domainBand(hsl.red), orange: Self.domainBand(hsl.orange),
            yellow: Self.domainBand(hsl.yellow), green: Self.domainBand(hsl.green),
            aqua: Self.domainBand(hsl.aqua), blue: Self.domainBand(hsl.blue),
            purple: Self.domainBand(hsl.purple), magenta: Self.domainBand(hsl.magenta)
        )
        return updated
    }

    func prettyPrinted() -> String {
        let encoder = JSONEncoder()
        // No `.sortedKeys` — Foundation's `JSONEncoder` otherwise preserves each key's `encode(to:)`
        // call order, which (via `CodingKeys`' own declared order above) matches the Preset Tuning
        // Panel spec's own example JSON field order.
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
