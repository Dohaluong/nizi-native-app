//
//  CubeLUTLoader.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import Foundation

/// Production `LUTLoading` — reads a `.cube` file, parses it with `CubeFileParser`, and caches the
/// parsed `Data` so the same LUT is never re-parsed for the lifetime of this instance (ADDEDUM.md
/// § 7, § 15: "LUT chỉ parse một lần"). 13 bundled presets ship a real `.cube` each (see
/// `PHOTO-EDITOR-PRESET-GUIDE.md`); a user-imported preset's `.cube` lives in
/// `DocumentsCustomLUTFileStore`'s directory instead, checked first — `resourceName` is always
/// just a plain filename either way, so callers never need to know which source it came from.
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

        let url = try resolveURL(for: resourceName)
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

    private func resolveURL(for resourceName: String) throws -> URL {
        let documentsCandidate = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DocumentsCustomLUTFileStore.subdirectoryName, isDirectory: true)
            .appendingPathComponent(resourceName)
        if FileManager.default.fileExists(atPath: documentsCandidate.path) {
            return documentsCandidate
        }

        // Flat bundle lookup, no subdirectory — matches `BundleAlbumLayoutRepository`'s own
        // convention for this project's synchronized-group Xcode target (Nizi/Features/.../*.json
        // still lands at the bundle root, not under its source subfolder).
        let name = (resourceName as NSString).deletingPathExtension
        let ext = (resourceName as NSString).pathExtension
        guard let url = bundle.url(forResource: name, withExtension: ext.isEmpty ? "cube" : ext) else {
            throw LUTLoadingError.resourceNotFound
        }
        return url
    }

    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
}
