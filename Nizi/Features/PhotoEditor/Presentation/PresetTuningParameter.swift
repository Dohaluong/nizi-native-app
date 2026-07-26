//
//  PresetTuningParameter.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Drives every slider in the DEBUG-only Preset Tuning Panel — same "one enum + get/set through a
/// `PresetDefinition`" shape `AdjustParameter` already uses for `PhotoAdjustments`, just over a much
/// larger field set and with a per-parameter *display* range/unit, since the panel's sliders are
/// meant to read the way a developer would type them into a Lightroom-style tool (EV, -100...100
/// percent, 0...100), not the engine's internal -1...1/0...1 storage.
///
/// English-only labels, not routed through `Localizable.xcstrings` — unlike every other user-facing
/// string in this app (ARCHITECTURE.md § 5), this screen is DEBUG-only tooling for the developer
/// doing the color grading, never shown to an end user, so the usual bilingual-catalog requirement
/// is deliberately not applied here.
enum PresetTuningParameter: String, CaseIterable, Identifiable {
    case toneCurve
    case exposure, contrast, highlights, shadows, blacks, whites
    case saturation, vibrance, warmth, tint
    case bloom, grain, vignette, sharpness, clarity

    var id: String { rawValue }

    enum Section: String, CaseIterable {
        case toneCurve = "Tone Curve"
        case tone = "Tone"
        case color = "Color"
        case style = "Style"
    }

    static let bySection: [(Section, [PresetTuningParameter])] = [
        (.toneCurve, [.toneCurve]),
        (.tone, [.exposure, .contrast, .highlights, .shadows, .blacks, .whites]),
        (.color, [.saturation, .vibrance, .warmth, .tint]),
        (.style, [.bloom, .grain, .vignette, .sharpness, .clarity]),
    ]

    var title: String {
        switch self {
        case .toneCurve: "Tone Curve (S-curve strength)"
        case .exposure: "Exposure"
        case .contrast: "Contrast"
        case .highlights: "Highlights"
        case .shadows: "Shadows"
        case .blacks: "Blacks"
        case .whites: "Whites"
        case .saturation: "Saturation"
        case .vibrance: "Vibrance"
        case .warmth: "Warmth"
        case .tint: "Tint (Green ↔ Magenta)"
        case .bloom: "Bloom"
        case .grain: "Grain"
        case .vignette: "Vignette"
        case .sharpness: "Sharpness"
        case .clarity: "Clarity (TODO — no engine yet)"
        }
    }

    /// The range + unit a developer actually drags — `-1.5...1.5` EV for exposure (the spec's own
    /// wording), `-100...100` percent for most tone/color sliders, `0...100` for the always-positive
    /// style effects.
    var displayRange: ClosedRange<Double> {
        switch self {
        case .exposure: -1.5...1.5
        case .toneCurve, .contrast, .highlights, .shadows, .blacks, .whites,
             .saturation, .vibrance, .warmth, .tint, .clarity:
            -100...100
        case .bloom, .grain, .vignette, .sharpness:
            0...100
        }
    }

    var isClarityTODO: Bool { self == .clarity }

    func displayValue(in preset: PresetDefinition) -> Double {
        switch self {
        case .toneCurve: Double(preset.toneCurveAmount) * 100
        case .exposure: Double(preset.exposureOffset) * 2.0
        case .contrast: Double(preset.contrastOffset) * 100
        case .highlights: Double(preset.highlightsOffset) * 100
        case .shadows: Double(preset.shadowsOffset) * 100
        case .blacks: Double(preset.blacksOffset) * 100
        case .whites: Double(preset.whitesOffset) * 100
        case .saturation: Double(preset.saturationOffset) * 100
        case .vibrance: Double(preset.vibranceOffset) * 100
        case .warmth: Double(preset.warmthOffset) * 100
        case .tint: Double(preset.tintOffset) * 100
        case .bloom: Double(preset.bloomAmount) * 100
        case .grain: Double(preset.grainAmount) * 100
        case .vignette: Double(preset.vignetteAmount) * 100
        case .sharpness: Double(preset.sharpnessAmount) * 100
        case .clarity: Double(preset.clarityOffset) * 100
        }
    }

    /// Sensible fixed radius/size for the three effects whose secondary parameter (`bloomRadius`/
    /// `grainSize`/`vignetteRadius`) the panel's spec doesn't expose its own slider for — applied
    /// only the moment an effect's amount goes from `0` to something nonzero on a preset that never
    /// had a radius/size of its own (e.g. every real shipped LUT preset today, which uses none of
    /// these effects), so raising the slider doesn't silently produce a zero-radius no-op.
    func setDisplayValue(_ value: Double, in preset: inout PresetDefinition) {
        switch self {
        case .toneCurve: preset.toneCurveAmount = Float(value / 100)
        case .exposure: preset.exposureOffset = Float(value / 2.0)
        case .contrast: preset.contrastOffset = Float(value / 100)
        case .highlights: preset.highlightsOffset = Float(value / 100)
        case .shadows: preset.shadowsOffset = Float(value / 100)
        case .blacks: preset.blacksOffset = Float(value / 100)
        case .whites: preset.whitesOffset = Float(value / 100)
        case .saturation: preset.saturationOffset = Float(value / 100)
        case .vibrance: preset.vibranceOffset = Float(value / 100)
        case .warmth: preset.warmthOffset = Float(value / 100)
        case .tint: preset.tintOffset = Float(value / 100)
        case .bloom:
            preset.bloomAmount = Float(value / 100)
            if preset.bloomAmount > 0, preset.bloomRadius == 0 { preset.bloomRadius = 8 }
        case .grain:
            preset.grainAmount = Float(value / 100)
            if preset.grainAmount > 0, preset.grainSize == 0 { preset.grainSize = 1 }
        case .vignette:
            preset.vignetteAmount = Float(value / 100)
            if preset.vignetteAmount > 0, preset.vignetteRadius == 0 { preset.vignetteRadius = 1.5 }
        case .sharpness: preset.sharpnessAmount = Float(value / 100)
        case .clarity: preset.clarityOffset = Float(value / 100)
        }
    }
}
