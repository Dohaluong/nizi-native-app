//
//  MockAlbumPhotoProvider.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import UIKit

/// For SwiftUI Previews and tests only — never requires Photos Library access. Production
/// `AlbumDetailView`/viewer must not default to this (docs/specs/SPEC-REAL-ALBUM.md § 35.2).
struct MockAlbumPhotoProvider: AlbumPhotoProviding {
    func loadImage(request: AlbumPhotoRequest) -> AsyncStream<AlbumPhotoLoadState> {
        AsyncStream { continuation in
            continuation.yield(.loading)
            let image = Self.solidColorImage(seed: request.reference.id, size: request.targetPixelSize)
            continuation.yield(.success(image))
            continuation.finish()
        }
    }

    func cancelRequest(for requestId: UUID) async {}

    private static func solidColorImage(seed: String, size: CGSize) -> UIImage {
        let safeSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        let hue = CGFloat(abs(seed.hashValue) % 360) / 360
        let color = UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1)
        let renderer = UIGraphicsImageRenderer(size: safeSize)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: safeSize))
        }
    }
}
