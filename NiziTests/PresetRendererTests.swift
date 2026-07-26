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

    /// Regression test for a real bug: `PresetRenderer.blend()`'s final `forceOpaqueAlpha` step ran
    /// a `CIColorMatrix` with a non-zero `biasVector` and never cropped the result back to the
    /// input's extent. Core Image correctly reports `CGRect.infinite` as a biased color matrix's
    /// output extent (the bias covers the whole infinite canvas, not just the finite input), so
    /// `PhotoRenderEngine.render` then asked `CIContext` to rasterize an infinite rect — producing
    /// a blank/failed render every time any real preset (not just Original) was selected, with no
    /// crash: the editor silently kept showing whatever was already on screen, which read as "the
    /// LUT preset never applies."
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
    /// via a standalone diagnostic), yet the amplified color blend at a typical 85% preset intensity
    /// (150% amplification → an effective 127.5% crossfade factor) came out visibly *darker* than
    /// the source. Root cause: `blend()`'s scale+add math ran in Core Image's default linear-light
    /// working space, where extrapolating a crossfade factor past 100% clips shadow detail to black
    /// far more aggressively than the same nominal amplification looks like in gamma/perceptual
    /// space. `blend()` now runs that math on `gammaSpace`-encoded values instead — this asserts a
    /// brightening LUT's blended output average brightness doesn't drop below the *source* image's
    /// own average, which the pre-fix linear-space blend violated by 20-50% on every real LUT tested.
    @Test
    func amplifiedBlendOfABrighteningLUTStaysNoDarkerThanSource() {
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
}
