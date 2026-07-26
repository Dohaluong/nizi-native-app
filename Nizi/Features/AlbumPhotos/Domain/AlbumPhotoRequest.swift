//
//  AlbumPhotoRequest.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import CoreGraphics
import Foundation

/// This module's own content-mode enum — deliberately not the Layout Engine's
/// `AlbumSlotContentMode`, so `Features/AlbumPhotos` never has to import
/// `Features/AlbumLayout` just to describe how an image fills a rectangle (docs/specs/
/// SPEC-REAL-ALBUM.md § 4: keep Photos loading independent of the Layout Engine). The
/// Presentation-layer bridge between the two converts at the boundary.
enum AlbumPhotoContentMode: String, Sendable {
    case fit
    case fill
}

enum AlbumPhotoDeliveryMode: String, Sendable {
    case fast
    case opportunistic
    case highQuality
}

struct AlbumPhotoRequest: Hashable, Sendable {
    let reference: AlbumPhotoReference
    let targetPixelSize: CGSize
    let contentMode: AlbumPhotoContentMode
    let deliveryMode: AlbumPhotoDeliveryMode
}
