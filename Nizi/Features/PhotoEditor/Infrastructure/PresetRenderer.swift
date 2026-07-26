//
//  PresetRenderer.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies one `PresetDefinition` at a given intensity to a `CIImage`:
/// `LUT blend (0...100%, capped) → Tone Curve → signature adjustments (contrast/highlights/
/// shadows/warmth/saturation/vibrance/blacks/whites/tint) → texture (grain/bloom/vignette/
/// sharpness)`. The LUT's only job is the color transform itself; a preset's *strength*/character
/// comes from the Tone Curve and signature adjustments layered after it, both of which scale
/// cleanly with intensity — unlike a fixed 3D LUT, which has no well-defined meaning past "100% of
/// what the vendor authored."
protocol PresetRendering: Sendable {
    func applyPreset(_ preset: PresetDefinition, intensity: Float, to input: CIImage) -> CIImage
}

struct PresetRenderer: PresetRendering {
    let lutLoader: LUTLoading

    init(lutLoader: LUTLoading = CubeLUTLoader()) {
        self.lutLoader = lutLoader
    }

    /// `strength` drives the LUT blend, Tone Curve, and every signature adjustment uniformly —
    /// production never extrapolates any of them past `intensity`'s own `0...1` range (a past
    /// version amplified the LUT blend to 150% of `intensity`, which — combined with a linear-space
    /// blend bug — made every preset render visibly darker than intended; see `blend`'s doc comment
    /// and `docs/modules/photo-editor/` history). Texture keeps its own existing sub-curves
    /// (`applyTexture`), unchanged.
    func applyPreset(_ preset: PresetDefinition, intensity: Float, to input: CIImage) -> CIImage {
        guard !preset.isOriginal, intensity > 0 else { return input }
        let strength = min(max(intensity, 0), 1)

        let afterLUT = applyLUT(preset: preset, strength: strength, to: input)
        let afterCurve = applyToneCurve(preset: preset, strength: strength, to: afterLUT)
        let afterSignature = applySignatureAdjustments(preset: preset, strength: strength, to: afterCurve)
        return applyTexture(preset: preset, intensity: strength, to: afterSignature)
    }

    // MARK: - LUT (color transform only — no strength-scaling of the cube itself, just of the
    // blend toward its result)

    private func applyLUT(preset: PresetDefinition, strength: Float, to image: CIImage) -> CIImage {
        guard let lutResource = preset.lutResource, let dimension = preset.lutDimension else {
            return image
        }
        guard let cube = try? lutLoader.loadCube(resourceName: lutResource, dimension: dimension) else {
            // A missing/malformed LUT resource must not crash the render or drop the whole
            // preset — fall back to the un-LUT'd image.
            return image
        }
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(cube.dimension)
        filter.cubeData = cube.data
        filter.colorSpace = cube.colorSpace
        let styled = filter.outputImage ?? image

        // `strength` is already clamped to `0...1` by `applyPreset` — this is a plain crossfade,
        // never an extrapolation past the vendor's own LUT result.
        return Self.blend(original: image, styled: styled, factor: strength)
    }

    /// `Output = Original × (1 - factor) + Styled × factor`, `factor` always in `0...1` (never
    /// extrapolated in production — `applyPreset` clamps `strength` before calling this).
    ///
    /// A standard alpha-composite crossfade — `styled`'s alpha channel scaled to `factor`, then
    /// `CISourceOverCompositing` over the opaque `original` — not the per-channel RGB scaling +
    /// `CIAdditionCompositing` approach a previous version used (which existed specifically to
    /// support `factor > 1` extrapolation, a feature production no longer has any use for since
    /// LUT strength is now always capped `0...1`). That approach is also the reason this reverted:
    /// a standalone diagnostic (built while investigating a user-reported over-darkening bug) found
    /// that `CIColorMatrix` scaling composed with `CIAdditionCompositing` introduces an *inconsistent*
    /// implicit gamma round-trip when rendered — even a plain identity crossfade (`factor` values
    /// nowhere near an edge case) came out roughly half brightness, regardless of whether the scale
    /// math ran in Core Image's default linear working space or was wrapped in an explicit gamma
    /// encode/decode. `CISourceOverCompositing`, by contrast, is Core Image's purpose-built
    /// compositing primitive — verified via the same diagnostic to track a plain linear
    /// interpolation between `original` and `styled` to within ~1% at every `factor` from `0` to
    /// `1`, with no gamma wrapping needed at all.
    private static func blend(original: CIImage, styled: CIImage, factor: Float) -> CIImage {
        guard factor != 1 else { return styled }
        guard factor != 0 else { return original }

        let alphaMatrix = CIFilter.colorMatrix()
        alphaMatrix.inputImage = styled
        alphaMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        alphaMatrix.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        alphaMatrix.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        alphaMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(factor))
        let styledWithAlpha = alphaMatrix.outputImage ?? styled

        let over = CIFilter.sourceOverCompositing()
        over.inputImage = styledWithAlpha
        over.backgroundImage = original
        return over.outputImage ?? styled
    }

    // MARK: - Tone Curve (signature strength, not a fixed per-preset LUT)

    /// A parametric film-style S-curve, not 5 freely-authored control points — `toneCurveAmount`
    /// (`-1...1`) scales how far quarter-/three-quarter-tone move from the identity diagonal, while
    /// pure black/white (`point0`/`point4`) stay anchored so this only ever adds/removes midtone
    /// contrast, never crushes/blows either endpoint on its own. Deliberately simple (same
    /// "swappable heuristic, not final color science" spirit `PhotoToneAdjuster` already documents)
    /// — a real curve editor with freely draggable points is future work, not V1.
    private func applyToneCurve(preset: PresetDefinition, strength: Float, to image: CIImage) -> CIImage {
        let amount = CGFloat(min(max(preset.toneCurveAmount, -1), 1)) * CGFloat(strength)
        guard amount != 0 else { return image }

        let filter = CIFilter.toneCurve()
        filter.inputImage = image
        let shift = amount * 0.12
        filter.point0 = CGPoint(x: 0, y: 0)
        filter.point1 = CGPoint(x: 0.25, y: min(max(0.25 - shift, 0), 1))
        filter.point2 = CGPoint(x: 0.5, y: 0.5)
        filter.point3 = CGPoint(x: 0.75, y: min(max(0.75 + shift, 0), 1))
        filter.point4 = CGPoint(x: 1, y: 1)
        return filter.outputImage ?? image
    }

    // MARK: - Signature adjustments (ADDEDUM § 8.1 — a preset's own baked-in tone, on top of the
    // LUT + Tone Curve, not the six-parameter production Adjust feature)

    /// Every offset is scaled by `strength` before reaching `PhotoToneAdjuster` — at 100% intensity
    /// a signature adjustment applies exactly as authored; below that, it fades out proportionally,
    /// same as texture already does.
    private func applySignatureAdjustments(preset: PresetDefinition, strength: Float, to image: CIImage) -> CIImage {
        var result = PhotoToneAdjuster.apply(
            exposure: preset.exposureOffset * strength,
            contrast: preset.contrastOffset * strength,
            highlights: preset.highlightsOffset * strength,
            shadows: preset.shadowsOffset * strength,
            warmth: preset.warmthOffset * strength,
            saturation: preset.saturationOffset * strength,
            // "Fade" (spec: a lifted-shadows, lower-contrast matte look) maps onto the existing
            // shadow-lift half of `blacksOffset`'s levels stretch — no separate `fadeAmount` field;
            // a positive `blacksOffset` already lifts the black point exactly the way a classic
            // film "fade" does.
            blacks: preset.blacksOffset * strength,
            whites: preset.whitesOffset * strength,
            vibrance: preset.vibranceOffset * strength,
            tint: preset.tintOffset * strength,
            to: image
        )
        if preset.isMonochrome {
            let filter = CIFilter.colorControls()
            filter.inputImage = result
            filter.saturation = 0
            result = filter.outputImage ?? result
        }
        return result
    }

    // MARK: - Texture style (ADDEDUM § 8.2 — non-linear vs. the color blend above)

    private func applyTexture(preset: PresetDefinition, intensity: Float, to image: CIImage) -> CIImage {
        let grainIntensity = min(preset.grainAmount * (0.4 + intensity * 0.6), preset.grainAmount)
        let bloomIntensity = preset.bloomAmount * intensity
        let vignetteIntensity = preset.vignetteAmount * intensity
        let sharpenIntensity = preset.sharpnessAmount * intensity

        var result = image
        result = Self.applyBloom(amount: bloomIntensity, radius: preset.bloomRadius, to: result)
        result = Self.applyVignette(amount: vignetteIntensity, radius: preset.vignetteRadius, to: result)
        result = Self.applyGrain(amount: grainIntensity, size: preset.grainSize, to: result)
        result = Self.applySharpen(amount: sharpenIntensity, to: result)
        return result
    }

    private static func applySharpen(amount: Float, to image: CIImage) -> CIImage {
        guard amount > 0 else { return image }
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        // `CISharpenLuminance`'s own default is `0.4` at a nominal "fully on" setting — `amount`
        // here is already `0...1`-ish (`sharpnessAmount * intensity`), so `* 2` maps it onto
        // roughly `0...2`, the filter's documented useful range.
        filter.sharpness = amount * 2
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    private static func applyVignette(amount: Float, radius: Float, to image: CIImage) -> CIImage {
        guard amount > 0 else { return image }
        let filter = CIFilter.vignette()
        filter.inputImage = image
        filter.intensity = amount * 2
        filter.radius = radius
        return filter.outputImage ?? image
    }

    private static func applyBloom(amount: Float, radius: Float, to image: CIImage) -> CIImage {
        guard amount > 0 else { return image }
        let filter = CIFilter.bloom()
        filter.inputImage = image
        filter.intensity = amount
        filter.radius = radius
        // `CIBloom` can expand its output extent slightly beyond the source — cropped back so it
        // never surprises a caller expecting the same extent it passed in.
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    /// No stock "film grain" filter exists in Core Image — this composites desaturated, mostly-
    /// transparent `CIRandomGenerator` noise over the image via a soft-light blend, scaled by
    /// `amount`. A serviceable, honestly-approximate prototype effect (ADDEDUM § 12: not worth
    /// over-engineering for V1), swappable for a real grain algorithm without touching the rest of
    /// this pipeline.
    private static func applyGrain(amount: Float, size: Float, to image: CIImage) -> CIImage {
        guard amount > 0 else { return image }
        guard let rawNoise = CIFilter.randomGenerator().outputImage else { return image }

        let noiseScale = max(0.2, Double(size))
        let scaledNoise = rawNoise
            .transformed(by: CGAffineTransform(scaleX: noiseScale, y: noiseScale))
            .cropped(to: image.extent)

        let desaturate = CIFilter.colorControls()
        desaturate.inputImage = scaledNoise
        desaturate.saturation = 0
        desaturate.contrast = 1.02
        let desaturatedNoise = desaturate.outputImage ?? scaledNoise

        // Kept subtle even at `amount == 1` — grain is a texture accent, not a filter that should
        // ever dominate the photo.
        let opacity = Double(min(max(amount, 0), 1)) * 0.35
        let fade = CIFilter.colorMatrix()
        fade.inputImage = desaturatedNoise
        fade.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
        let fadedNoise = fade.outputImage ?? desaturatedNoise

        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = fadedNoise
        blend.backgroundImage = image
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }
}
