//
//  PresetRendererTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import CoreImage
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

    private static func makePreset(intensity: Float = 0.85) -> PresetDefinition {
        PresetDefinition(
            id: "test-preset", name: "Test", shortName: "Test",
            nameKey: "test.name", shortNameKey: "test.shortName",
            lutResource: "fake.cube", lutDimension: 2,
            defaultIntensity: intensity,
            exposureOffset: 0, contrastOffset: 0, saturationOffset: 0, warmthOffset: 0,
            highlightsOffset: 0, shadowsOffset: 0,
            grainAmount: 0, grainSize: 0, bloomAmount: 0, bloomRadius: 0,
            vignetteAmount: 0, vignetteRadius: 0,
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
}
