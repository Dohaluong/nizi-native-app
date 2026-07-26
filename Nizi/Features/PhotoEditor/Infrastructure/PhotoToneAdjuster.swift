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
    /// `blacks`/`whites`/`vibrance`/`tint` default to `0` (no-op) — the production Adjust feature
    /// (`PhotoRenderEngine.applyRecipe` → `PhotoAdjustments`) is deliberately locked to the
    /// original six parameters (PHOTO-EDITOR.md V1 scope) and never passes these; only
    /// `PresetRenderer.applyBaseTone` (a preset's own baked-in tone, tunable via the DEBUG-only
    /// Preset Tuning Panel) supplies them.
    static func apply(
        exposure: Float,
        contrast: Float,
        highlights: Float,
        shadows: Float,
        warmth: Float,
        saturation: Float,
        blacks: Float = 0,
        whites: Float = 0,
        vibrance: Float = 0,
        tint: Float = 0,
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

        // `CIVibrance` boosts already-muted colors more than already-saturated ones (and is more
        // skin-tone-safe) — a separate stage from the `saturation` above, not a replacement for it,
        // so a preset can use either or both independently (ADDEDUM-adjacent Preset Tuning Panel
        // spec: "Ưu tiên Vibrance hơn Saturation").
        if vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = result
            filter.amount = vibrance
            result = filter.outputImage ?? result
        }

        if warmth != 0 || tint != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = result
            let neutralTemperature: CGFloat = 6500
            filter.neutral = CIVector(x: neutralTemperature, y: 0)
            // Positive warmth → lower target temperature than the neutral point → the filter
            // shifts the image warmer (more orange); negative → cooler (more blue). `tint` is the
            // same filter's other axis (green ↔ magenta) — positive shifts magenta, negative
            // shifts green.
            filter.targetNeutral = CIVector(
                x: neutralTemperature - CGFloat(warmth) * 1500,
                y: CGFloat(tint) * 100
            )
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

        if blacks != 0 || whites != 0 {
            result = applyLevels(blacks: blacks, whites: whites, to: result)
        }

        return result
    }

    /// A coarse "endpoint" stretch, applied after highlight/shadow recovery — positive `blacks`
    /// lifts the black point (brightens/flattens shadows), negative crushes it further; positive
    /// `whites` extends the white point brighter (more blowout), negative pulls it down
    /// (recovers). Implemented as `output = (input - lo) / (hi - lo)` via `CIColorMatrix`
    /// scale+bias, same "deliberately simple, swappable heuristic" spirit as the rest of this
    /// pipeline — not a real levels/curves engine.
    private static func applyLevels(blacks: Float, whites: Float, to image: CIImage) -> CIImage {
        let lo = CGFloat(-blacks * 0.25)
        let hi = CGFloat(1 - whites * 0.25)
        let scale = 1 / max(hi - lo, 0.01)
        let bias = -lo * scale

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        // Same infinite-extent pitfall `PresetRenderer.forceOpaqueAlpha` hit — a non-zero bias on
        // `CIColorMatrix` makes Core Image report `CGRect.infinite`, since the bias would apply
        // even to the conceptually-clear region outside the source. Crop back immediately.
        return (matrix.outputImage ?? image).cropped(to: image.extent)
    }
}
