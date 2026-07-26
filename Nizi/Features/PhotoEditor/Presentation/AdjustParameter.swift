//
//  AdjustParameter.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// The six Adjust sliders, exactly (PHOTO-EDITOR.md § 8.1) — no others may be added. A UI-facing
/// selector for which `PhotoAdjustments` field a slider is currently editing; the underlying
/// storage stays the plain `PhotoAdjustments` struct, this just maps a case to its field.
enum AdjustParameter: String, CaseIterable, Identifiable, Sendable {
    case exposure
    case contrast
    case highlights
    case shadows
    case warmth
    case saturation

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .exposure: "photoEditor.adjust.exposure"
        case .contrast: "photoEditor.adjust.contrast"
        case .highlights: "photoEditor.adjust.highlights"
        case .shadows: "photoEditor.adjust.shadows"
        case .warmth: "photoEditor.adjust.warmth"
        case .saturation: "photoEditor.adjust.saturation"
        }
    }

    func value(in adjustments: PhotoAdjustments) -> Float {
        switch self {
        case .exposure: adjustments.exposure
        case .contrast: adjustments.contrast
        case .highlights: adjustments.highlights
        case .shadows: adjustments.shadows
        case .warmth: adjustments.warmth
        case .saturation: adjustments.saturation
        }
    }

    func setting(_ value: Float, in adjustments: inout PhotoAdjustments) {
        switch self {
        case .exposure: adjustments.exposure = value
        case .contrast: adjustments.contrast = value
        case .highlights: adjustments.highlights = value
        case .shadows: adjustments.shadows = value
        case .warmth: adjustments.warmth = value
        case .saturation: adjustments.saturation = value
        }
    }
}
