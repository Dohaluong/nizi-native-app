//
//  MockPhotoRendering.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// A `PhotoRendering` that never touches the Photos Library or Core Image — for SwiftUI Previews
/// and standalone QA only (mirrors `MockAlbumPhotoProvider`'s role for `AlbumPhotoProviding`).
/// Must never be the default in `PhotoEditorView`'s production initializer.
struct MockPhotoRendering: PhotoRendering {
    func renderPreview(photoId: String, recipe: PhotoEditRecipe, targetSize: CGSize) async throws -> CGImage {
        try await Task.sleep(nanoseconds: 300_000_000)
        return Self.placeholderImage(for: photoId, recipe: recipe, size: targetSize)
    }

    func renderFullResolution(photoId: String, recipe: PhotoEditRecipe) async throws -> CGImage {
        try await Task.sleep(nanoseconds: 300_000_000)
        return Self.placeholderImage(for: photoId, recipe: recipe, size: CGSize(width: 3000, height: 3000))
    }

    /// A distinctly-colored square (derived from `photoId`) so different mock photo ids are
    /// visually distinguishable — same idea, and same stable-hash requirement (never
    /// `String.hashValue`, per docs/specs/SPEC-MODIFY-DRAFT.md § 11), as
    /// `DistinguishableMockPhotoProvider` uses for Album's own previews. Original vs. edited is
    /// distinguished by brightness, so the hold-to-compare gesture has something visible to show
    /// even with no real render pipeline behind it yet.
    private static func placeholderImage(for photoId: String, recipe: PhotoEditRecipe, size: CGSize) -> CGImage {
        let hue = Double(stableHash(photoId) % 360) / 360
        let brightness = recipe.isUnedited ? 0.55 : 0.7
        let color = UIColor(hue: hue, saturation: 0.45, brightness: brightness, alpha: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        // Safe to force-unwrap: `UIGraphicsImageRenderer` always produces a backed `CGImage` for a
        // plain fill (no unsupported color space/format involved).
        return image.cgImage!
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
