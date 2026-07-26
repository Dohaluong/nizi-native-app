//
//  ImageAnalyzer.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import CoreImage

/// Measures a `CIImage`'s basic tonal/color characteristics by downsampling it to a small pixel
/// grid and reading raw bytes directly — a real, on-device histogram/brightness analysis
/// (PHOTO-EDITOR.md § 9.1), not a stub. Deliberately simple: this is a rule-based heuristic input,
/// not a precision measurement, so a small sample (e.g. 64×64) is plenty and keeps analysis fast.
enum ImageAnalyzer {
    /// Sampled pixels darker than this (on a 0...1 brightness scale) count toward
    /// `shadowClippingRatio`.
    private static let shadowThreshold: Float = 0.08
    /// Sampled pixels brighter than this count toward `highlightClippingRatio`.
    private static let highlightThreshold: Float = 0.92

    static func analyze(_ image: CIImage, using ciContext: CIContext, sampleDimension: Int = 64) -> PhotoHistogramStatistics? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, sampleDimension > 0 else { return nil }

        let scale = CGFloat(sampleDimension) / max(extent.width, extent.height)
        let downsampled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(downsampled, from: downsampled.extent) else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        guard let bitmapContext = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixelCount = width * height
        var totalBrightness: Double = 0
        var totalSaturation: Double = 0
        var shadowCount = 0
        var highlightCount = 0

        for pixelIndex in 0..<pixelCount {
            let offset = pixelIndex * 4
            let r = Double(pixelData[offset]) / 255
            let g = Double(pixelData[offset + 1]) / 255
            let b = Double(pixelData[offset + 2]) / 255

            let brightness = (r + g + b) / 3
            let maxComponent = max(r, g, b)
            let minComponent = min(r, g, b)
            let saturation = maxComponent > 0 ? (maxComponent - minComponent) / maxComponent : 0

            totalBrightness += brightness
            totalSaturation += saturation
            if brightness < Double(shadowThreshold) { shadowCount += 1 }
            if brightness > Double(highlightThreshold) { highlightCount += 1 }
        }

        return PhotoHistogramStatistics(
            averageBrightness: Float(totalBrightness / Double(pixelCount)),
            shadowClippingRatio: Float(Double(shadowCount) / Double(pixelCount)),
            highlightClippingRatio: Float(Double(highlightCount) / Double(pixelCount)),
            averageSaturation: Float(totalSaturation / Double(pixelCount))
        )
    }
}
