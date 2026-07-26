//
//  PhotoHistogramStatistics.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// A photo's basic tonal/color characteristics — what `AutoEnhanceRules` reasons about
/// (PHOTO-EDITOR.md § 9.1: "Độ sáng tổng thể, Vùng bị tối, Vùng highlight quá mạnh... Độ bão
/// hòa"). Produced by `ImageAnalyzer` from a downsampled pixel sample, never from a full-
/// resolution image — this is a cheap heuristic, not a precise measurement.
struct PhotoHistogramStatistics: Equatable, Sendable {
    /// `0...1` — mean of (R+G+B)/3 across sampled pixels.
    var averageBrightness: Float
    /// `0...1` — fraction of sampled pixels darker than a near-black threshold.
    var shadowClippingRatio: Float
    /// `0...1` — fraction of sampled pixels brighter than a near-white threshold.
    var highlightClippingRatio: Float
    /// `0...1` — mean HSB saturation across sampled pixels.
    var averageSaturation: Float
}
