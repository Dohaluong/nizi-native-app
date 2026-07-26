//
//  AlbumImageCacheTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import UIKit
import Testing
@testable import Nizi

/// docs/specs/SPEC-REAL-ALBUM.md § 36.4
struct AlbumImageCacheTests {
    private func makeImage(color: UIColor = .red, size: CGSize = CGSize(width: 4, height: 4)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func sameKeyReturnsSameImage() {
        let cache = AlbumImageCache()
        let key = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 300, height: 300), contentMode: .fill)
        let image = makeImage()
        cache.store(image, for: key)
        #expect(cache.image(for: key) === image)
    }

    @Test func differentTargetBucketProducesADifferentKey() {
        let small = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 100, height: 100), contentMode: .fill)
        let large = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 900, height: 900), contentMode: .fill)
        #expect(small != large)
    }

    @Test func sameSourceIdentifierAtDifferentSizesDoNotCollide() {
        let cache = AlbumImageCache()
        let thumbnailKey = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 100, height: 100), contentMode: .fill)
        let coverKey = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 1200, height: 1200), contentMode: .fill)

        let thumbnailImage = makeImage(color: .red)
        let coverImage = makeImage(color: .blue)
        cache.store(thumbnailImage, for: thumbnailKey)
        cache.store(coverImage, for: coverKey)

        #expect(cache.image(for: thumbnailKey) === thumbnailImage)
        #expect(cache.image(for: coverKey) === coverImage)
    }

    @Test func purgeRemovesEverything() {
        let cache = AlbumImageCache()
        let key = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 300, height: 300), contentMode: .fill)
        cache.store(makeImage(), for: key)
        #expect(cache.image(for: key) != nil)

        cache.removeAll()
        #expect(cache.image(for: key) == nil)
    }

    @Test func contentModeIsPartOfTheKey() {
        let fillKey = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 300, height: 300), contentMode: .fill)
        let fitKey = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 300, height: 300), contentMode: .fit)
        #expect(fillKey != fitKey)
    }

    @Test func nearbySizesShareABucket() {
        // Within the 50px bucket, two very close requests should collide (by design) rather than
        // fragmenting the cache — § 9.1's point is to *avoid* "unique identifier for every size."
        let a = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 300, height: 300), contentMode: .fill)
        let b = AlbumImageCacheKey(sourceIdentifier: "asset-1", targetPixelSize: CGSize(width: 305, height: 302), contentMode: .fill)
        #expect(a == b)
    }
}
