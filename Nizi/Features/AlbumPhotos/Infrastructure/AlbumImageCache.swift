//
//  AlbumImageCache.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import CoreGraphics
import Foundation
import UIKit

/// Never just the photo ID — the same photo is requested at very different sizes (thumbnail,
/// Page Viewer, cover), and those must not collide in the cache (docs/specs/SPEC-REAL-ALBUM.md
/// § 9.1). Sizes are bucketed (rounded) rather than used exactly, so two requests that are a
/// pixel apart still hit the same cache entry.
struct AlbumImageCacheKey: Hashable {
    let sourceIdentifier: String
    let widthBucket: Int
    let heightBucket: Int
    let contentMode: AlbumPhotoContentMode

    /// Buckets to the nearest 50px — fine enough that visually-identical requests share a cache
    /// entry, coarse enough that trivial layout jitter doesn't fragment the cache.
    init(sourceIdentifier: String, targetPixelSize: CGSize, contentMode: AlbumPhotoContentMode) {
        self.sourceIdentifier = sourceIdentifier
        widthBucket = Int((targetPixelSize.width / 50).rounded()) * 50
        heightBucket = Int((targetPixelSize.height / 50).rounded()) * 50
        self.contentMode = contentMode
    }
}

/// `NSCache`-backed — no disk cache this sprint (§ 9.2). Only ever holds already-resized display
/// images, never full-resolution originals (§ 9.3, § 30).
final class AlbumImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, PlatformImage>()

    init(countLimit: Int = 200) {
        cache.countLimit = countLimit
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil
        )
    }

    func image(for key: AlbumImageCacheKey) -> PlatformImage? {
        cache.object(forKey: cacheKeyString(key) as NSString)
    }

    func store(_ image: PlatformImage, for key: AlbumImageCacheKey) {
        cache.setObject(image, forKey: cacheKeyString(key) as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func cacheKeyString(_ key: AlbumImageCacheKey) -> String {
        "\(key.sourceIdentifier)|\(key.widthBucket)x\(key.heightBucket)|\(key.contentMode.rawValue)"
    }

    @objc private func handleMemoryWarning() {
        cache.removeAllObjects()
    }
}
