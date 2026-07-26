//
//  CubeLUTLoader.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import Foundation

/// Production `LUTLoading` — reads a `.cube` file from the app bundle, parses it with
/// `CubeFileParser`, and caches the parsed `Data` so the same LUT is never re-parsed for the
/// lifetime of this instance (ADDEDUM.md § 7, § 15: "LUT chỉ parse một lần"). No V1 preset
/// actually ships a `.cube` yet (see `PresetDefinition.isPrototype`), but this is a real, working
/// implementation, not a stub — swapping in an official LUT later needs zero changes here.
final class CubeLUTLoader: LUTLoading, @unchecked Sendable {
    private let bundle: Bundle
    private let cache = NSCache<NSString, NSData>()

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadCube(resourceName: String, dimension: Int) throws -> LUTCube {
        let cacheKey = "\(resourceName)#\(dimension)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return LUTCube(dimension: dimension, data: cached as Data, colorSpace: Self.colorSpace)
        }

        // Flat bundle lookup, no subdirectory — matches `BundleAlbumLayoutRepository`'s own
        // convention for this project's synchronized-group Xcode target (Nizi/Features/.../*.json
        // still lands at the bundle root, not under its source subfolder).
        let name = (resourceName as NSString).deletingPathExtension
        let ext = (resourceName as NSString).pathExtension
        guard let url = bundle.url(forResource: name, withExtension: ext.isEmpty ? "cube" : ext) else {
            throw LUTLoadingError.resourceNotFound
        }

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw LUTLoadingError.resourceNotFound
        }

        let parsedData = try CubeFileParser.parse(text: text, expectedDimension: dimension)
        cache.setObject(parsedData as NSData, forKey: cacheKey)
        return LUTCube(dimension: dimension, data: parsedData, colorSpace: Self.colorSpace)
    }

    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
}
