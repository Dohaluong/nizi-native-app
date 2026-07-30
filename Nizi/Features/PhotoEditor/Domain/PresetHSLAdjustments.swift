//
//  PresetHSLAdjustments.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import Foundation

/// One of the 8 selective-color bands the Preset Tuning Panel's HSL tool exposes — evenly spaced
/// 45° apart around the hue wheel, in the same Red→Orange→Yellow→Green→Aqua→Blue→Purple→Magenta
/// order the reference tool's own swatch row uses. `PresetRenderer.applySelectiveHSL` blends each
/// band's own Hue/Saturation/Lightness offset by how close a pixel's actual hue is to `hueDegrees`
/// (a linear falloff to zero at ±45°) — evenly-spaced 45° centers is what makes every hue's two
/// nearest bands' weights sum to exactly 1 with no separate normalization pass required.
enum HSLColorBand: String, CaseIterable, Codable, Identifiable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    var id: String { rawValue }

    var hueDegrees: Float {
        switch self {
        case .red: 0
        case .orange: 45
        case .yellow: 90
        case .green: 135
        case .aqua: 180
        case .blue: 225
        case .purple: 270
        case .magenta: 315
        }
    }
}

/// One band's own Hue/Saturation/Lightness offset — every field a normalized `-1...1`, same
/// convention every other `PresetDefinition` offset uses. `PresetTuningPanelView`'s HSL sliders
/// (via `HSLTuningComponent`) scale these to their own display range (± degrees for hue, ±
/// percent for saturation/lightness) the same way `PresetTuningParameter` already does for every
/// other field.
struct HSLBandAdjustment: Codable, Equatable, Sendable {
    var hue: Float = 0
    var saturation: Float = 0
    var lightness: Float = 0

    var isIdentity: Bool { hue == 0 && saturation == 0 && lightness == 0 }
}

/// All 8 bands' own offsets for one `PresetDefinition` — named fields (not a `Dictionary<HSLColorBand,
/// _>`, which would round-trip through JSON as an alternating key/value array instead of a real
/// keyed object) so `presets.json`/the Preset Tuning Panel's "Copy JSON" both produce a plain,
/// readable `{"red": {...}, "orange": {...}, ...}` shape.
struct PresetHSLAdjustments: Codable, Equatable, Sendable {
    var red = HSLBandAdjustment()
    var orange = HSLBandAdjustment()
    var yellow = HSLBandAdjustment()
    var green = HSLBandAdjustment()
    var aqua = HSLBandAdjustment()
    var blue = HSLBandAdjustment()
    var purple = HSLBandAdjustment()
    var magenta = HSLBandAdjustment()

    static let identity = PresetHSLAdjustments()

    var isIdentity: Bool {
        HSLColorBand.allCases.allSatisfy { self[$0].isIdentity }
    }

    /// All 8 bands paired with their own offset, in wheel order — what
    /// `PresetRenderer.applySelectiveHSL`'s per-pixel blend loops over.
    var allBands: [(band: HSLColorBand, adjustment: HSLBandAdjustment)] {
        HSLColorBand.allCases.map { ($0, self[$0]) }
    }

    subscript(band: HSLColorBand) -> HSLBandAdjustment {
        get {
            switch band {
            case .red: red
            case .orange: orange
            case .yellow: yellow
            case .green: green
            case .aqua: aqua
            case .blue: blue
            case .purple: purple
            case .magenta: magenta
            }
        }
        set {
            switch band {
            case .red: red = newValue
            case .orange: orange = newValue
            case .yellow: yellow = newValue
            case .green: green = newValue
            case .aqua: aqua = newValue
            case .blue: blue = newValue
            case .purple: purple = newValue
            case .magenta: magenta = newValue
            }
        }
    }
}
