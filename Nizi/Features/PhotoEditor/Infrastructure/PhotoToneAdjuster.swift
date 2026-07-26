//
//  PhotoToneAdjuster.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreImage
import CoreImage.CIFilterBuiltins

/// Maps the six shared tone parameters (exposure/contrast/highlights/shadows/warmth/saturation —
/// the same six `PhotoAdjustments` names Bước 5's manual Adjust sliders use) onto stock Core Image
/// filters. Used by `PresetRenderer` for a preset's own "base tone" (ADDEDUM.md § 8.1) today;
/// Bước 5 calls this same function for the user's manual Adjust values instead of re-deriving its
/// own filter mapping, since both are mechanically "nudge exposure/contrast/etc. via Core Image" —
/// only *what* supplies the six numbers differs (a preset's fixed offsets vs. `PhotoAdjustments`
/// live slider values).
///
/// Every offset is a normalized `-1...1`-ish value (`PhotoAdjustments`/`PresetDefinition`'s own
/// convention) — deliberately simple, swappable heuristics appropriate for V1 prototype color
/// (ADDEDUM § 12: "Không dành quá nhiều thời gian cố mô phỏng" a specific film stock), not
/// final-tuned color science.
enum PhotoToneAdjuster {
    static func apply(
        exposure: Float,
        contrast: Float,
        highlights: Float,
        shadows: Float,
        warmth: Float,
        saturation: Float,
        to image: CIImage
    ) -> CIImage {
        var result = image

        if exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = result
            filter.ev = exposure * 2.0 // ±1 normalized → ±2 EV
            result = filter.outputImage ?? result
        }

        if contrast != 0 || saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = result
            filter.contrast = 1.0 + contrast * 0.5 // ±1 → 0.5...1.5
            filter.saturation = max(0, 1.0 + saturation * 0.8) // ±1 → 0.2...1.8, never negative
            filter.brightness = 0
            result = filter.outputImage ?? result
        }

        if warmth != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = result
            let neutralTemperature: CGFloat = 6500
            filter.neutral = CIVector(x: neutralTemperature, y: 0)
            // Positive warmth → lower target temperature than the neutral point → the filter
            // shifts the image warmer (more orange); negative → cooler (more blue).
            filter.targetNeutral = CIVector(x: neutralTemperature - CGFloat(warmth) * 1500, y: 0)
            result = filter.outputImage ?? result
        }

        if highlights != 0 || shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = result
            // `CIHighlightShadowAdjust` only exposes 0...1 on each side (default highlightAmount
            // 1 = unchanged, default shadowAmount 0 = unchanged) — it can recover blown highlights
            // and lift crushed shadows, but can't push either past the source's own range. Good
            // enough for prototype presets; a real highlight/shadow curve is future work, not V1.
            filter.highlightAmount = Float(min(max(1.0 - highlights, 0), 1))
            filter.shadowAmount = Float(min(max(shadows, 0), 1))
            result = filter.outputImage ?? result
        }

        return result
    }
}
