//
//  PresetRenderer.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies one `PresetDefinition` at a given intensity to a `CIImage` — ADDEDUM.md § 9's pipeline:
/// base tone → optional LUT → linear blend against the original by intensity → texture (grain/
/// bloom/vignette), which fades by its own, non-linear coefficients (§ 8.2), not the same curve
/// the color blend uses.
protocol PresetRendering: Sendable {
    func applyPreset(_ preset: PresetDefinition, intensity: Float, to input: CIImage) -> CIImage
}

struct PresetRenderer: PresetRendering {
    let lutLoader: LUTLoading

    /// User feedback (after shipping the 13 real LUTs): a plain 1:1 LUT application read as too
    /// subtle. This amplifies the *color* blend past the raw LUT result — at UI intensity 100%,
    /// the effective color-blend factor is 150% of a pure single LUT application, extrapolating
    /// the color shift further in the same direction rather than capping at "however strong the
    /// vendor's LUT alone is." Texture (grain/bloom/vignette) intentionally is not amplified by
    /// this — none of the 13 shipped LUT presets uses texture, and over-driving grain/vignette the
    /// same way tends to look broken rather than punchier.
    static let colorIntensityAmplification: Float = 1.5

    init(lutLoader: LUTLoading = CubeLUTLoader()) {
        self.lutLoader = lutLoader
    }

    func applyPreset(_ preset: PresetDefinition, intensity: Float, to input: CIImage) -> CIImage {
        guard !preset.isOriginal, intensity > 0 else { return input }

        let styled = applyLUTIfNeeded(preset: preset, to: applyBaseTone(preset: preset, to: input))
        let colorBlendFactor = intensity * Self.colorIntensityAmplification
        let colorBlended = Self.blend(original: input, styled: styled, factor: colorBlendFactor)
        return applyTexture(preset: preset, intensity: intensity, to: colorBlended)
    }

    // MARK: - Color style (ADDEDUM § 8.1)

    private func applyBaseTone(preset: PresetDefinition, to image: CIImage) -> CIImage {
        var result = PhotoToneAdjuster.apply(
            exposure: preset.exposureOffset,
            contrast: preset.contrastOffset,
            highlights: preset.highlightsOffset,
            shadows: preset.shadowsOffset,
            warmth: preset.warmthOffset,
            saturation: preset.saturationOffset,
            blacks: preset.blacksOffset,
            whites: preset.whitesOffset,
            vibrance: preset.vibranceOffset,
            tint: preset.tintOffset,
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

    private func applyLUTIfNeeded(preset: PresetDefinition, to image: CIImage) -> CIImage {
        guard let lutResource = preset.lutResource, let dimension = preset.lutDimension else {
            return image
        }
        guard let cube = try? lutLoader.loadCube(resourceName: lutResource, dimension: dimension) else {
            // A missing/malformed LUT resource must not crash the render or drop the whole
            // preset — fall back to whatever the base tone adjustments already produced.
            return image
        }
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(cube.dimension)
        filter.cubeData = cube.data
        filter.colorSpace = cube.colorSpace
        return filter.outputImage ?? image
    }

    /// `Output = Original × (1 - factor) + Styled × factor` (§ 7.3's formula), generalized to
    /// `factor` values outside `0...1` — `PhotoEditRecipe.presetIntensity` itself always stays
    /// `0...1` (§ 10), but `applyPreset` can hand this an amplified `factor` above `1` to
    /// extrapolate the color shift further than a single LUT application, or (in principle) below
    /// `0` to push in the opposite direction.
    ///
    /// Implemented via per-channel RGB scaling + `CIAdditionCompositing`, not alpha-channel
    /// scaling + `over`-compositing (the previous approach) — alpha is only ever valid in
    /// `0...1`, so it silently clamps `factor` right back to a plain LUT application above 100%,
    /// which is exactly the amplification this exists to allow. `forceOpaqueAlpha` resets alpha to
    /// a clean `1.0` afterward, since adding two alpha-1 layers would otherwise leave alpha at `2`,
    /// which the texture stage's own `over`/blend-mode compositing depends on being correct.
    ///
    /// The scale+add math itself runs on `gammaSpace`-encoded values, not Core Image's default
    /// (linear-light) working space — a real bug found via user report + a standalone diagnostic:
    /// extrapolating `factor > 1` in *linear* light space clips shadows to black far more
    /// aggressively than the same nominal amplification looks like in gamma/perceptual space
    /// (linear values compress shadow detail into a tiny numeric range, so subtracting even a
    /// modest `(1 - factor)`-scaled `original` term pushes them hard negative). Measured on the 4
    /// most extreme shipped LUTs at 85% intensity (150% amplification): linear-space blending
    /// darkened the output 20–27% versus the *pure*, unamplified LUT (which is itself 0–8%
    /// *brighter* than the source) — gamma-space blending cuts that down to 5–14%. The direction of
    /// `matchedToWorkingSpace(from:)`/`matchedFromWorkingSpace(to:)` below was picked by testing
    /// both and keeping the one that actually reduced the darkening, not by relying on the API
    /// names alone. A residual few-percent darkening still remains — extrapolation past 100%
    /// clipped at `0...1` is inherently lossy in the shadows/highlights it clips, whichever space
    /// it runs in.
    private static let gammaSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func blend(original: CIImage, styled: CIImage, factor: Float) -> CIImage {
        guard factor != 1 else { return styled }
        guard factor != 0 else { return original }

        guard let originalGamma = original.matchedToWorkingSpace(from: gammaSpace),
              let styledGamma = styled.matchedToWorkingSpace(from: gammaSpace) else {
            // Color-space matching unavailable for this image — fall back to the plain linear-space
            // blend rather than failing the render entirely.
            let originalScaled = scaleRGB(original, by: 1 - factor)
            let styledScaled = scaleRGB(styled, by: factor)
            let add = CIFilter.additionCompositing()
            add.inputImage = styledScaled
            add.backgroundImage = originalScaled
            return forceOpaqueAlpha(add.outputImage ?? styled)
        }

        let originalScaled = scaleRGB(originalGamma, by: 1 - factor)
        let styledScaled = scaleRGB(styledGamma, by: factor)

        let add = CIFilter.additionCompositing()
        add.inputImage = styledScaled
        add.backgroundImage = originalScaled
        let summedGamma = forceOpaqueAlpha(add.outputImage ?? styledGamma)

        return summedGamma.matchedFromWorkingSpace(to: gammaSpace) ?? summedGamma
    }

    /// Scales RGB by `factor` (which may be negative or greater than 1 — Core Image's internal
    /// pipeline works in extended-range float and only clamps to `0...1` at final rasterization,
    /// same as any other over-driven adjustment clipping at pure black/white), leaving alpha
    /// untouched.
    private static func scaleRGB(_ image: CIImage, by factor: Float) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        let f = CGFloat(factor)
        matrix.rVector = CIVector(x: f, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: f, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: f, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage ?? image
    }

    private static func forceOpaqueAlpha(_ image: CIImage) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        // A non-zero `biasVector` makes Core Image treat the *entire infinite canvas* as
        // non-transparent output (bias is added even where the source is conceptually clear
        // outside `image.extent`), so `matrix.outputImage.extent` comes back as `CGRect.infinite`
        // rather than the finite extent that went in. `PhotoRenderEngine.render` then calls
        // `ciContext.createCGImage(image, from: image.extent)` with that infinite rect, which
        // silently produces a blank/failed render — exactly why a selected preset never appeared
        // to apply. Cropping back to the pre-bias extent is what `applyBloom` already does for
        // the same underlying reason, just a much larger blow-up here.
        return (matrix.outputImage ?? image).cropped(to: image.extent)
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
