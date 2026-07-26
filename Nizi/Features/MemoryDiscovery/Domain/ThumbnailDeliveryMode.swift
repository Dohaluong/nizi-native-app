//
//  ThumbnailDeliveryMode.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Maps to `PHImageRequestOptions.deliveryMode` — kept as a Domain-level enum so Presentation
/// never has to import Photos just to pick a delivery mode.
enum ThumbnailDeliveryMode {
    /// PhotoKit's fast/"degraded" delivery — quick, lower resolution, served from on-device
    /// caches only. Use for anything the user is actively waiting to see, like opening a preview.
    case fast
    /// PhotoKit's high-quality delivery — slower, especially for an asset not yet downloaded
    /// locally. Use only when the image itself is being analyzed (e.g. Vision quality scoring),
    /// not just displayed.
    case highQuality
}
