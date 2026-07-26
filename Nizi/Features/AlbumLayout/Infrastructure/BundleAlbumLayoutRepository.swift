//
//  BundleAlbumLayoutRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Reads `album-layouts.json` from an app bundle, decodes it, validates it once
/// (`AlbumLayoutValidator`), and caches the result in memory — the JSON is never re-read or
/// re-decoded on subsequent calls (§ Performance). A library that fails validation is never
/// cached; every call re-throws the same failure until a valid bundle is provided.
final class BundleAlbumLayoutRepository: AlbumLayoutRepository {
    private let bundle: Bundle
    private let resourceName: String
    private var cachedLibrary: AlbumLayoutLibrary?

    init(bundle: Bundle = .main, resourceName: String = "album-layouts") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func loadLibrary() throws -> AlbumLayoutLibrary {
        if let cachedLibrary {
            return cachedLibrary
        }

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw AlbumLayoutError.resourceNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AlbumLayoutError.resourceNotFound
        }

        let library: AlbumLayoutLibrary
        do {
            library = try JSONDecoder().decode(AlbumLayoutLibrary.self, from: data)
        } catch {
            throw AlbumLayoutError.decodingFailed(String(describing: error))
        }

        try AlbumLayoutValidator.validate(library)

        cachedLibrary = library
        return library
    }

    func layout(id: String) throws -> AlbumPageLayout {
        let library = try loadLibrary()
        guard let match = library.layouts.first(where: { $0.id == id }) else {
            throw AlbumLayoutError.layoutNotFound(id)
        }
        return match
    }

    func layouts(photoCount: Int, format: AlbumPageFormat) throws -> [AlbumPageLayout] {
        let library = try loadLibrary()
        return library.layouts.filter { $0.photoCount == photoCount && $0.supportedFormats.contains(format) }
    }
}
