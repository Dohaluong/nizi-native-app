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

    init(lutLoader: LUTLoading = CubeLUTLoader()) {
        self.lutLoader = lutLoader
    }

    func applyPreset(_ preset: PresetDefinition, intensity: Float, to input: CIImage) -> CIImage {
        guard !preset.isOriginal, intensity > 0 else { return input }

        let styled = applyLUTIfNeeded(preset: preset, to: applyBaseTone(preset: preset, to: input))
        let colorBlended = Self.blend(original: input, styled: styled, intensity: intensity)
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

    /// `Output = Original × (1 - intensity) + Styled × intensity` (§ 7.3's formula) — implemented
    /// as alpha-scaling `styled` to `intensity` and compositing it *over* the fully-opaque
    /// original, which is the exact linear cross-fade the formula describes (not a dissolve/
    /// dither transition, which would not be linear).
    private static func blend(original: CIImage, styled: CIImage, intensity: Float) -> CIImage {
        guard intensity < 1 else { return styled }
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = styled
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity))
        let alphaScaled = matrix.outputImage ?? styled
        return alphaScaled.composited(over: original)
    }

    // MARK: - Texture style (ADDEDUM § 8.2 — non-linear vs. the color blend above)

    private func applyTexture(preset: PresetDefinition, intensity: Float, to image: CIImage) -> CIImage {
        let grainIntensity = min(preset.grainAmount * (0.4 + intensity * 0.6), preset.grainAmount)
        let bloomIntensity = preset.bloomAmount * intensity
        let vignetteIntensity = preset.vignetteAmount * intensity

        var result = image
        result = Self.applyBloom(amount: bloomIntensity, radius: preset.bloomRadius, to: result)
        result = Self.applyVignette(amount: vignetteIntensity, radius: preset.vignetteRadius, to: result)
        result = Self.applyGrain(amount: grainIntensity, size: preset.grainSize, to: result)
        return result
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
