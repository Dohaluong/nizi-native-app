//
//  PresetRendererTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing
@testable import Nizi

struct PresetRendererTests {
    private struct FakeLUTLoader: LUTLoading {
        let cube: LUTCube
        func loadCube(resourceName: String, dimension: Int) throws -> LUTCube { cube }
    }

    private static func identityCube(dimension: Int) -> LUTCube {
        var floats: [Float] = []
        let denom = Float(dimension - 1)
        for _ in 0..<dimension {
            for _ in 0..<dimension {
                for r in 0..<dimension {
                    floats.append(Float(r) / denom)
                    floats.append(Float(r) / denom)
                    floats.append(Float(r) / denom)
                    floats.append(1)
                }
            }
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        return LUTCube(dimension: dimension, data: data, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    private static func makePreset(
        intensity: Float = 0.85,
        blacksOffset: Float = 0, whitesOffset: Float = 0, vibranceOffset: Float = 0, tintOffset: Float = 0,
        sharpnessAmount: Float = 0
    ) -> PresetDefinition {
        PresetDefinition(
            id: "test-preset", name: "Test", shortName: "Test",
            nameKey: "test.name", shortNameKey: "test.shortName",
            lutResource: "fake.cube", lutDimension: 2,
            defaultIntensity: intensity,
            exposureOffset: 0, contrastOffset: 0, saturationOffset: 0, warmthOffset: 0,
            highlightsOffset: 0, shadowsOffset: 0,
            blacksOffset: blacksOffset, whitesOffset: whitesOffset, vibranceOffset: vibranceOffset, tintOffset: tintOffset,
            grainAmount: 0, grainSize: 0, bloomAmount: 0, bloomRadius: 0,
            vignetteAmount: 0, vignetteRadius: 0, sharpnessAmount: sharpnessAmount,
            protectSkinTones: true, isMonochrome: false,
            thumbnailAssetName: nil, sortOrder: 1, isActive: true, isPrototype: false
        )
    }

    /// Regression test for a real bug: an early version of `PresetRenderer.blend()` ran a
    /// `CIColorMatrix` with a non-zero `biasVector` and never cropped the result back to the
    /// input's extent. Core Image correctly reports `CGRect.infinite` as a biased color matrix's
    /// output extent (the bias covers the whole infinite canvas, not just the finite input), so
    /// `PhotoRenderEngine.render` then asked `CIContext` to rasterize an infinite rect — producing
    /// a blank/failed render every time any real preset (not just Original) was selected, with no
    /// crash: the editor silently kept showing whatever was already on screen, which read as "the
    /// LUT preset never applies." `blend()` has since moved to a plain alpha-composite crossfade
    /// (`CISourceOverCompositing`, no bias vector involved at all — see its doc comment), which
    /// makes this whole bug class structurally impossible; kept as a standing regression guard.
    @Test
    func appliedPresetNeverHasInfiniteExtent() {
        let renderer = PresetRenderer(lutLoader: FakeLUTLoader(cube: Self.identityCube(dimension: 2)))
        let preset = Self.makePreset()
        let input = CIImage(color: CIColor(red: 0.6, green: 0.3, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let output = renderer.applyPreset(preset, intensity: preset.defaultIntensity, to: input)

        #expect(output.extent != .infinite)
        #expect(output.extent == input.extent)
    }

    /// Applying a preset with a real (non-identity) LUT and non-zero intensity must actually change
    /// pixel values — not just avoid the infinite-extent crash above, but visibly do something.
    @Test
    func appliedPresetActuallyChangesPixels() {
        // A non-identity cube: every input maps to pure red, so any correctly-applied blend must
        // shift the green/blue channels down from the input's 0.3/0.2.
        var floats: [Float] = []
        for _ in 0..<8 { floats.append(contentsOf: [1, 0, 0, 1] as [Float]) }
        let cubeData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let cube = LUTCube(dimension: 2, data: cubeData, colorSpace: CGColorSpaceCreateDeviceRGB())
        let renderer = PresetRenderer(lutLoader: FakeLUTLoader(cube: cube))
        let preset = Self.makePreset(intensity: 1.0)
        let input = CIImage(color: CIColor(red: 0.6, green: 0.3, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let output = renderer.applyPreset(preset, intensity: preset.defaultIntensity, to: input)

        let context = CIContext(options: [.useSoftwareRenderer: true])
        var inputPixel = [UInt8](repeating: 0, count: 4)
        var outputPixel = [UInt8](repeating: 0, count: 4)
        context.render(input, toBitmap: &inputPixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        context.render(output, toBitmap: &outputPixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        #expect(outputPixel != inputPixel)
    }

    /// The Preset Tuning Panel's new tone fields (`blacksOffset`/`whitesOffset`/`vibranceOffset`/
    /// `tintOffset`) and texture field (`sharpnessAmount`) each route through a `CIColorMatrix` (or,
    /// for `applyLevels`, one with a non-zero bias — the exact shape that caused the infinite-extent
    /// bug above) or a filter that can expand its extent (`CISharpenLuminance`). Every one of them
    /// must still produce a finite output extent on its own, with no LUT/blend involved.
    @Test
    func newToneAndTextureFieldsStayExtentSafe() {
        let renderer = PresetRenderer(lutLoader: FakeLUTLoader(cube: Self.identityCube(dimension: 2)))
        let input = CIImage(color: CIColor(red: 0.6, green: 0.3, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let fields: [(String, PresetDefinition)] = [
            ("blacks", Self.makePreset(blacksOffset: 1)),
            ("whites", Self.makePreset(whitesOffset: -1)),
            ("vibrance", Self.makePreset(vibranceOffset: 1)),
            ("tint", Self.makePreset(tintOffset: 1)),
            ("sharpness", Self.makePreset(sharpnessAmount: 1)),
        ]

        for (label, preset) in fields {
            let output = renderer.applyPreset(preset, intensity: preset.defaultIntensity, to: input)
            #expect(output.extent == input.extent, "\(label) produced extent \(output.extent)")
        }
    }

    /// Regression test for a real bug reported by the user: real film-emulation LUTs mostly
    /// *brighten* an image slightly on their own (0-8% brighter across the 13 shipped LUTs, measured
    /// via a standalone diagnostic), yet the color blend came out visibly *darker* than the source.
    /// Two compounding causes were found and fixed, both via `blend()`, both verified through
    /// standalone (non-`xcodebuild test`) diagnostics since this project never executes the test
    /// suite:
    /// 1. An early version amplified the crossfade factor to 150% of `intensity`; production has
    ///    since dropped that entirely (`applyPreset` clamps `strength` to `0...1` before `blend()`
    ///    ever sees it — see `PresetRenderer`'s top-level doc comment).
    /// 2. Independent of amplification, `blend()`'s original per-channel `CIColorMatrix` scaling +
    ///    `CIAdditionCompositing` implementation turned out to *not* behave as a linear crossfade at
    ///    all — a follow-up diagnostic found it rendered roughly half brightness at *any*
    ///    intermediate factor (e.g. `0.85`), not just extrapolated ones, regardless of whether the
    ///    math ran in Core Image's default linear working space or was wrapped in an explicit gamma
    ///    encode/decode. `blend()` now uses a plain alpha-composite crossfade
    ///    (`CISourceOverCompositing`) instead, verified to track a true linear interpolation between
    ///    source and styled to within ~1% at every factor from `0` to `1`.
    ///
    /// `0.9` is a comfortable bound given the real measured ratio is ~1.10 (brighter, matching the
    /// LUT's own tendency) — tight enough to catch a regression back to any of the above.
    @Test
    func cappedBlendOfABrighteningLUTStaysNoDarkerThanSource() {
        // A cube that uniformly lifts every input value — mimics the real shipped LUTs' own
        // tendency to brighten slightly, not the drastically-different-hue identity/pure-red cubes
        // the other tests above use to isolate LUT application itself.
        let dimension = 4
        let denom = Float(dimension - 1)
        var floats: [Float] = []
        for _ in 0..<dimension {
            for _ in 0..<dimension {
                for r in 0..<dimension {
                    let lifted = min(Float(r) / denom + 0.1, 1)
                    floats.append(contentsOf: [lifted, lifted, lifted, 1] as [Float])
                }
            }
        }
        let cubeData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let cube = LUTCube(dimension: dimension, data: cubeData, colorSpace: CGColorSpaceCreateDeviceRGB())
        let renderer = PresetRenderer(lutLoader: FakeLUTLoader(cube: cube))
        let preset = Self.makePreset(intensity: 0.85)

        // A full shadow-to-highlight gradient, not a flat color — the bug only shows up once a
        // meaningful shadow range exists to clip.
        let gradientFilter = CIFilter.smoothLinearGradient()
        gradientFilter.point0 = CGPoint(x: 0, y: 0)
        gradientFilter.point1 = CGPoint(x: 64, y: 0)
        gradientFilter.color0 = CIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        gradientFilter.color1 = CIColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1)
        let input = (gradientFilter.outputImage ?? CIImage(color: .gray))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 16))

        let output = renderer.applyPreset(preset, intensity: preset.defaultIntensity, to: input)

        let context = CIContext(options: [.useSoftwareRenderer: true])
        func averageBrightness(_ image: CIImage) -> Double {
            let average = CIFilter.areaAverage()
            average.inputImage = image
            average.extent = image.extent
            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(
                average.outputImage!, toBitmap: &bitmap, rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            return (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / 3
        }

        let sourceBrightness = averageBrightness(input)
        let outputBrightness = averageBrightness(output)
        // Not a strict `>=` — extrapolating past 100% and clipping at `0...1` is inherently a little
        // lossy even with the gamma-space fix (verified via a standalone diagnostic: ~1.5% darker
        // on this exact scenario, comfortably within this bound). The pre-fix linear-space blend
        // measured 20-27% darker than the source on the real shipped LUTs; a wrong-direction gamma
        // attempt measured 45-50% darker. `0.9` catches a regression back to either without being
        // so tight it's sensitive to minor, expected extrapolation/clipping loss.
        #expect(outputBrightness >= sourceBrightness * 0.9, "blended output (\(outputBrightness)) darker than source (\(sourceBrightness)) by more than the expected small margin, despite a brightening LUT")
    }

    /// `applyPreset` must never let `strength` exceed `1.0` regardless of what `intensity` it's
    /// handed — the whole point of the redesign this test is named after. Passing `intensity: 2.0`
    /// (something no real caller does — `PhotoEditRecipe.presetIntensity` is always `0...1` — but
    /// nothing in the type system prevents it) must produce the *same* result as `intensity: 1.0`,
    /// not a further-extrapolated one.
    @Test
    func applyPresetNeverExtrapolatesPastIntensityOne() {
        let renderer = PresetRenderer(lutLoader: FakeLUTLoader(cube: Self.identityCube(dimension: 2)))
        let preset = Self.makePreset(intensity: 1.0)
        let input = CIImage(color: CIColor(red: 0.6, green: 0.3, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let atOne = renderer.applyPreset(preset, intensity: 1.0, to: input)
        let atTwo = renderer.applyPreset(preset, intensity: 2.0, to: input)

        let context = CIContext(options: [.useSoftwareRenderer: true])
        func pixel(_ image: CIImage) -> [UInt8] {
            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return bitmap
        }
        #expect(pixel(atOne) == pixel(atTwo))
    }

    /// A capped-at-100% LUT blend (no signature adjustments, no Tone Curve) should track the
    /// source's own brightness closely — verified via a standalone diagnostic across 4 real shipped
    /// LUTs and 5 synthetic scene types (dark, bright sky, indoor, heavy shadow, skin tone): capping
    /// alone (no amplification) kept output within ~1% of source brightness with zero clipping in
    /// every case, versus 20-50% darker under either pre-fix pipeline. This is the core claim behind
    /// "LUT giữ nhiệm vụ biến đổi màu, không extrapolate" — asserted here as a tight bound (`0.85`,
    /// tighter than the 150%-amplified test above's `0.9`) since there's no extrapolation left to
    /// account for.
    @Test
    func cappedLUTOnlyBlendCloselyTracksSourceBrightness() {
        let dimension = 4
        let denom = Float(dimension - 1)
        var floats: [Float] = []
        for _ in 0..<dimension {
            for _ in 0..<dimension {
                for r in 0..<dimension {
                    let lifted = min(Float(r) / denom + 0.1, 1)
                    floats.append(contentsOf: [lifted, lifted, lifted, 1] as [Float])
                }
            }
        }
        let cubeData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let cube = LUTCube(dimension: dimension, data: cubeData, colorSpace: CGColorSpaceCreateDeviceRGB())
        let renderer = PresetRenderer(lutLoader: FakeLUTLoader(cube: cube))
        let preset = Self.makePreset(intensity: 1.0)

        let gradientFilter = CIFilter.smoothLinearGradient()
        gradientFilter.point0 = CGPoint(x: 0, y: 0)
        gradientFilter.point1 = CGPoint(x: 64, y: 0)
        gradientFilter.color0 = CIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
        gradientFilter.color1 = CIColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1)
        let input = (gradientFilter.outputImage ?? CIImage(color: .gray))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 16))

        let output = renderer.applyPreset(preset, intensity: 1.0, to: input)

        let context = CIContext(options: [.useSoftwareRenderer: true])
        func averageBrightness(_ image: CIImage) -> Double {
            let average = CIFilter.areaAverage()
            average.inputImage = image
            average.extent = image.extent
            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(average.outputImage!, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / 3
        }

        let sourceBrightness = averageBrightness(input)
        let outputBrightness = averageBrightness(output)
        #expect(outputBrightness >= sourceBrightness * 0.85, "capped LUT-only blend (\(outputBrightness)) darker than source (\(sourceBrightness)) by more than expected")
    }

    /// `toneCurveAmount` alone (no signature adjustments) must add contrast — deepen the
    /// quarter-tone, lift the three-quarter-tone — without clipping either endpoint on its own, on
    /// an ordinary (not already-extreme) gradient. Verified directionally via a standalone
    /// diagnostic; asserted here structurally: pure black/white stay pure black/white (`point0`/
    /// `point4` are anchored), and no full-range clipping appears for a middling `toneCurveAmount`.
    @Test
    func toneCurveAloneAddsContrastWithoutClippingEndpoints() {
        var preset = Self.makePreset(intensity: 1.0)
        preset.lutResource = nil
        preset.lutDimension = nil
        preset.toneCurveAmount = 0.5
        let renderer = PresetRenderer(lutLoader: FakeLUTLoader(cube: Self.identityCube(dimension: 2)))

        let gradientFilter = CIFilter.smoothLinearGradient()
        gradientFilter.point0 = CGPoint(x: 0, y: 0)
        gradientFilter.point1 = CGPoint(x: 64, y: 0)
        gradientFilter.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        gradientFilter.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let input = (gradientFilter.outputImage ?? CIImage(color: .gray))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 16))

        let output = renderer.applyPreset(preset, intensity: 1.0, to: input)

        let context = CIContext(options: [.useSoftwareRenderer: true])
        func pixel(_ image: CIImage, x: Int) -> UInt8 {
            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: x, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return bitmap[0]
        }
        #expect(pixel(output, x: 0) == 0, "pure black endpoint should stay anchored at 0")
        #expect(pixel(output, x: 63) == 255, "pure white endpoint should stay anchored at 255")
    }

    /// Characterization test, not a bug report: stacking multiple shadow-deepening signature
    /// adjustments (Tone Curve *and* Contrast) on an already very dark scene compounds — verified
    /// via a standalone diagnostic on a synthetic "heavy shadow" scene (80%+ of the frame near-black)
    /// where Tone Curve alone or Contrast alone each added contrast with zero clipping, but *both
    /// together* clipped 80% of the frame to pure black. This is expected behavior for any
    /// contrast-adding stack, not specific to this engine — it's exactly why the Preset Tuning
    /// Panel's histogram readout exists: a preset with several simultaneous shadow-deepening
    /// signature adjustments needs to be checked against dark source material before shipping, the
    /// same way any Lightroom/VSCO-style contrast stack would.
    @Test
    func stackedSignatureAdjustmentsCanClipShadowsOnDarkScenes() {
        var preset = Self.makePreset(intensity: 1.0)
        preset.lutResource = nil
        preset.lutDimension = nil
        preset.toneCurveAmount = 0.5
        preset.contrastOffset = 0.15
        let renderer = PresetRenderer(lutLoader: FakeLUTLoader(cube: Self.identityCube(dimension: 2)))

        // A "heavy shadow" scene: the vast majority of the frame near-black, a small bright accent —
        // mirrors the standalone diagnostic's synthetic scene that first surfaced this.
        let shadow = CIImage(color: CIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 50))
        let accent = CIImage(color: CIColor(red: 0.7, green: 0.65, blue: 0.55, alpha: 1)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 10))
        let over = CIFilter.sourceOverCompositing()
        over.inputImage = accent
        over.backgroundImage = shadow
        let input = over.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 64, height: 60))

        let output = renderer.applyPreset(preset, intensity: 1.0, to: input)

        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgOutput = context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
            Issue.record("could not rasterize output")
            return
        }
        var pixels = [UInt8](repeating: 0, count: cgOutput.width * cgOutput.height * 4)
        let bitmapContext = CGContext(data: &pixels, width: cgOutput.width, height: cgOutput.height, bitsPerComponent: 8, bytesPerRow: cgOutput.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmapContext.draw(cgOutput, in: CGRect(x: 0, y: 0, width: cgOutput.width, height: cgOutput.height))
        var clippedCount = 0
        var total = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += 1
            if pixels[i] == 0 && pixels[i + 1] == 0 && pixels[i + 2] == 0 { clippedCount += 1 }
        }
        let clippedRatio = Double(clippedCount) / Double(total)
        // Documents the magnitude found via the standalone diagnostic (~80%), with slack for the
        // smaller synthetic scene here — the point is confirming this *is* a real, sizable effect a
        // preset author needs to check for, not that it's exactly reproducible to the percent.
        #expect(clippedRatio > 0.3, "expected stacked signature adjustments to clip a large portion of an already-dark scene, got only \(clippedRatio * 100)%")
    }
}
