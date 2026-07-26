//
//  AlbumSlotPhotoProviding.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Decouples `AlbumPageRenderer` from where a photo's pixels actually come from — it never
/// imports `Photos`/`PHAsset` directly and never knows whether a reference resolves to a cached
/// thumbnail, an on-disk asset, or a placeholder (docs/specs/SPEC-REAL-ALBUM.md § 4: the renderer
/// only ever hands a slot a `photoReference`/`targetSize`/`contentMode`, never touches
/// `PHImageManager` itself). Preview screens implement this with SF Symbol/mock placeholders;
/// production Album screens implement it against `AlbumPhotoView` (Features/AlbumPhotos), which
/// is the one place that actually loads pixels via `ApplePhotosAlbumPhotoProvider`.
///
/// Named distinctly from `Features/AlbumPhotos/Application/AlbumPhotoProviding` — that's a lower
/// level "load image bytes for a reference" service; this is "what View does a rendered slot
/// show," which for production is *built on top of* the other one via `AlbumPhotoView`.
///
/// Lives in Presentation, not Domain: it returns a SwiftUI `View`, and Domain must stay free of
/// UI-framework imports (see docs/architecture/ARCHITECTURE.md § 3).
protocol AlbumSlotPhotoProviding {
    associatedtype PhotoContent: View

    @ViewBuilder
    func photoView(reference: AlbumPhotoReference, crop: AlbumPhotoCrop, contentMode: AlbumSlotContentMode) -> PhotoContent
}

/// Fixed SF Symbol + tint placeholder for every photo — used by the Layout Engine's own Preview
/// screens, which must work without Photos Library access or a simulator (§ Layout Gallery
/// Preview, § Album Pages Preview).
struct PlaceholderAlbumPhotoProvider: AlbumSlotPhotoProviding {
    var symbolName: String = "photo"

    func photoView(reference: AlbumPhotoReference, crop: AlbumPhotoCrop, contentMode: AlbumSlotContentMode) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.gray.opacity(0.22), Color.gray.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
        }
    }
}
