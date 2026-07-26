//
//  LUTLoading.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import Foundation

/// A parsed `.cube` 3D LUT, ready for `CIColorCubeWithColorSpace` — never re-parsed once loaded
/// (ADDEDUM.md § 7).
struct LUTCube: Equatable {
    let dimension: Int
    /// `dimension^3` RGBA `Float32` quadruples, in the order `CIColorCubeWithColorSpace` expects
    /// (blue slowest-varying, red fastest — the same order the `.cube` file format itself uses).
    let data: Data
    let colorSpace: CGColorSpace
}

/// Parses and caches `.cube` files — implementations must never re-parse the same resource twice
/// (ADDEDUM § 7: "Không parse lại file LUT mỗi lần kéo slider").
protocol LUTLoading: Sendable {
    func loadCube(resourceName: String, dimension: Int) throws -> LUTCube
}

enum LUTLoadingError: Error, Equatable {
    case resourceNotFound
    case invalidFormat
    case dimensionMismatch
}
