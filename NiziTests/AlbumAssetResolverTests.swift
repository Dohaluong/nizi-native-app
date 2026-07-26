//
//  AlbumAssetResolverTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Photos
import Testing
@testable import Nizi

/// Never touches real Photos Library access (docs/specs/SPEC-REAL-ALBUM.md § 36.2: "Không gọi
/// Photo Library thật trong unit test") — always returns `nil`, letting these tests exercise
/// `ApplePhotosAlbumPhotoProvider`'s missing-asset path, which is reachable without ever
/// constructing a real `PHAsset`.
private struct AlwaysMissingAssetResolver: PHAssetResolving {
    func asset(localIdentifier: String) async -> PHAsset? { nil }
}

struct AlbumAssetResolverTests {
    @Test func providerEmitsMissingWhenAssetResolverFindsNothing() async {
        let provider = ApplePhotosAlbumPhotoProvider(assetResolver: AlwaysMissingAssetResolver())
        let reference = AlbumPhotoReference(id: "gone", source: .applePhotos, sourceIdentifier: "gone", originalFilename: nil)
        let request = AlbumPhotoRequest(reference: reference, targetPixelSize: CGSize(width: 100, height: 100), contentMode: .fill, deliveryMode: .fast)

        var states: [String] = []
        for await state in provider.loadImage(request: request) {
            switch state {
            case .idle: states.append("idle")
            case .loading: states.append("loading")
            case .degraded: states.append("degraded")
            case .success: states.append("success")
            case .missing: states.append("missing")
            case .failure: states.append("failure")
            }
        }

        #expect(states.contains("missing"))
        #expect(!states.contains("success"))
    }

    @Test func missingAssetNeverCrashesOrHangs() async {
        // Regression guard: the whole point of this path is "handle missing assets without
        // crashing" (§ 34, § 37 acceptance #34) — simply completing this test (the `for await`
        // loop terminating) is the assertion.
        let provider = ApplePhotosAlbumPhotoProvider(assetResolver: AlwaysMissingAssetResolver())
        let reference = AlbumPhotoReference(id: "gone", source: .applePhotos, sourceIdentifier: "gone", originalFilename: nil)
        let request = AlbumPhotoRequest(reference: reference, targetPixelSize: CGSize(width: 50, height: 50), contentMode: .fit, deliveryMode: .fast)

        var completed = false
        for await _ in provider.loadImage(request: request) {}
        completed = true
        #expect(completed)
    }
}
