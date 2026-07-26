//
//  PhotoOrientation.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// A photo's shape, classified from its normalized pixel dimensions only — never from EXIF
/// orientation directly, since `pixelWidth`/`pixelHeight` are already the normalized
/// (already-rotated) dimensions the rest of the app works with. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 7.
enum PhotoOrientation: String, Codable, Hashable {
    case landscape
    case portrait
    case square

    /// `0.90...1.10` reads as `square`; outside that band, whichever side is longer wins.
    private static let squareToleranceRange = 0.90...1.10

    static func classify(width: Int, height: Int) -> PhotoOrientation? {
        guard width > 0, height > 0 else { return nil }
        let ratio = Double(width) / Double(height)
        if squareToleranceRange.contains(ratio) {
            return .square
        }
        return ratio > squareToleranceRange.upperBound ? .landscape : .portrait
    }
}
