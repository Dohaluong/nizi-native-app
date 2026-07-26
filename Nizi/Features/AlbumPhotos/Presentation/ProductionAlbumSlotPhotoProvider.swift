//
//  ProductionAlbumSlotPhotoProvider.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// The bridge between the Layout Engine's generic `AlbumSlotPhotoProviding` (Features/AlbumLayout)
/// and the real photo-loading stack (`AlbumPhotoView`/`AlbumPhotoProviding`, this module) — the
/// one place both modules meet. `AlbumPageRenderer` itself still never imports `Photos`
/// (docs/specs/SPEC-REAL-ALBUM.md § 4, § 11.1): it only ever calls this provider's
/// `photoView(reference:crop:contentMode:)`, exactly like every mock provider before it.
///
/// `AlbumPhotoView` receives `targetSize: nil` here deliberately — the renderer has already
/// constrained this slot to an exact `.frame(width:height:)` by the time this view is placed, so
/// `AlbumPhotoView`'s own `GeometryReader` fallback measures that *already-fixed* size and
/// multiplies by screen scale (§ 11.3), rather than this bridge needing to duplicate the
/// renderer's scale math.
struct ProductionAlbumSlotPhotoProvider: AlbumSlotPhotoProviding {
    func photoView(reference: AlbumPhotoReference, crop: AlbumPhotoCrop, contentMode: AlbumSlotContentMode) -> some View {
        AlbumPhotoView(reference: reference, crop: crop, contentMode: Self.convert(contentMode), targetSize: nil)
    }

    private static func convert(_ mode: AlbumSlotContentMode) -> AlbumPhotoContentMode {
        switch mode {
        case .fill: return .fill
        case .fit: return .fit
        }
    }
}
