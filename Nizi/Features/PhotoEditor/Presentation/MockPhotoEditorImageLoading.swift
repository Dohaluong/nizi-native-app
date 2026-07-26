//
//  MockPhotoEditorImageLoading.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// A `PhotoEditorImageLoading` that never touches the Photos Library — for SwiftUI Previews and
/// standalone QA only, mirroring `MockAlbumPhotoProvider`'s role for `AlbumPhotoProviding`. Must
/// never be the default in `PhotoEditorView`'s production initializer.
struct MockPhotoEditorImageLoading: PhotoEditorImageLoading {
    func loadPreview(photoId: String, targetSize: CGSize) async throws -> PlatformImage {
        try await Task.sleep(nanoseconds: 300_000_000)
        return Self.placeholderImage(for: photoId, size: targetSize)
    }

    /// A distinctly-colored square (derived from `photoId`) so different mock photo ids are
    /// visually distinguishable in Previews — same idea, and same stable-hash requirement, as
    /// `DistinguishableMockPhotoProvider` uses for Album's own previews. Never `String.hashValue`
    /// here — it isn't stable across process launches (docs/specs/SPEC-MODIFY-DRAFT.md § 11), so
    /// this uses the same FNV-1a approach instead.
    private static func placeholderImage(for photoId: String, size: CGSize) -> PlatformImage {
        let hue = Double(stableHash(photoId) % 360) / 360
        let color = UIColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for scalar in string.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
