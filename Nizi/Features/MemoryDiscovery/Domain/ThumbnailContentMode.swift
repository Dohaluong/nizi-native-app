//
//  ThumbnailContentMode.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Maps to `PHImageContentMode` — kept as a Domain-level enum so Presentation never has to
/// import Photos just to pick fill vs. fit.
enum ThumbnailContentMode {
    /// Crops to fill the target square — grid cells.
    case fill
    /// Letterboxes to fit within the target — full-screen viewing, never crops.
    case fit
}
