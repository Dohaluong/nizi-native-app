//
//  AutoEnhanceRules.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Turns `PhotoHistogramStatistics` into ordinary `PhotoAdjustments` — pure, rule-based, no ML/AI
/// (PHOTO-EDITOR.md § 9.1). Pure/testable off-device by design: this is the one place Auto
/// Enhance's actual "judgment" lives, kept separate from `ImageAnalyzer` (which only measures) and
/// `AutoEnhanceService` (which only orchestrates), so the rules themselves can be reasoned about
/// and tested without touching Core Image or PhotoKit.
///
/// § 9.3 — this must stay transparent: every value it produces lands in ordinary
/// `PhotoAdjustments` fields, visible and editable in the Adjust tab, never a hidden filter.
enum AutoEnhanceRules {
    /// Bumped whenever these heuristics change in a way that would alter previously-computed
    /// suggestions — stored on `PhotoEditRecipe.autoEnhanceVersion` so a saved recipe's Auto
    /// Enhance provenance is traceable.
    static let version = "1"

    static func suggestedAdjustments(for stats: PhotoHistogramStatistics) -> PhotoAdjustments {
        var adjustments = PhotoAdjustments()

        // Nudge toward a mid-gray target brightness — deliberately modest range so this always
        // reads as "an assist," never a drastic, surprising edit.
        let targetBrightness: Float = 0.45
        let brightnessDelta = targetBrightness - stats.averageBrightness
        if abs(brightnessDelta) > 0.03 {
            adjustments.exposure = clamp(brightnessDelta * 1.2, to: -0.35...0.35)
        }

        if stats.highlightClippingRatio > 0.05 {
            adjustments.highlights = clamp(-stats.highlightClippingRatio * 2.0, to: -0.5...0)
        }

        if stats.shadowClippingRatio > 0.05 {
            adjustments.shadows = clamp(stats.shadowClippingRatio * 2.0, to: 0...0.5)
        }

        if stats.averageSaturation < 0.18 {
            adjustments.saturation = 0.15
        }

        // A flat, low-contrast source (the case that triggered a real brightness correction
        // above) usually reads better with a small contrast nudge alongside it, not exposure alone.
        if abs(brightnessDelta) > 0.1 {
            adjustments.contrast = 0.08
        }

        return adjustments
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
