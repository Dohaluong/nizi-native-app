//
//  ImagePixelAnalyzer.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import CoreGraphics
import Foundation

/// Cheap, deterministic sharpness/exposure estimation from a small grayscale buffer — no Vision
/// model needed for these two. Blur via Laplacian variance (the same idea OpenCV's
/// `cv2.Laplacian(...).var()` blur check uses); exposure via mean brightness distance from mid-gray.
/// Reference constants are starting points, not tuned against a real library — see
/// docs/sprint/SPRINT-005B.md § 11.1–11.2.
enum ImagePixelAnalyzer {
    static func analyze(cgImage: CGImage, sampleSize: Int = 120) -> (sharpness: Double, exposure: Double) {
        guard let pixels = grayscalePixels(from: cgImage, targetSize: sampleSize) else {
            return (0.5, 0.5)
        }
        return (
            laplacianVarianceScore(pixels: pixels, width: sampleSize, height: sampleSize),
            exposureScore(pixels: pixels)
        )
    }

    private static func grayscalePixels(from cgImage: CGImage, targetSize: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: targetSize * targetSize)
        guard let context = CGContext(
            data: &pixels,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: targetSize,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        return pixels
    }

    private static func laplacianVarianceScore(pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width > 2, height > 2 else { return 0.5 }

        var laplacianValues: [Double] = []
        laplacianValues.reserveCapacity((width - 2) * (height - 2))

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(pixels[y * width + x])
                let up = Double(pixels[(y - 1) * width + x])
                let down = Double(pixels[(y + 1) * width + x])
                let left = Double(pixels[y * width + (x - 1)])
                let right = Double(pixels[y * width + (x + 1)])
                laplacianValues.append(4 * center - up - down - left - right)
            }
        }

        let mean = laplacianValues.reduce(0, +) / Double(laplacianValues.count)
        let variance = laplacianValues.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(laplacianValues.count)

        let referenceVariance = 400.0
        return min(variance / referenceVariance, 1.0)
    }

    private static func exposureScore(pixels: [UInt8]) -> Double {
        guard !pixels.isEmpty else { return 0.5 }
        let mean = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count)
        let distanceFromMid = abs(mean - 128) / 128
        return max(1 - distanceFromMid, 0)
    }
}
