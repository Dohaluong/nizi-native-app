//
//  MockAutoEnhancing.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// An `AutoEnhancing` that never touches the Photos Library or Core Image — for the standalone
/// preview harness only (mirrors `MockPhotoRendering`'s role). Returns a fixed, plausible-looking
/// suggestion so the Auto Enhance tab's "applied" state can be exercised without a real photo.
struct MockAutoEnhancing: AutoEnhancing {
    func analyze(photoId: String) async throws -> PhotoAdjustments {
        try await Task.sleep(nanoseconds: 400_000_000)
        var adjustments = PhotoAdjustments()
        adjustments.exposure = 0.12
        adjustments.highlights = -0.2
        adjustments.shadows = 0.15
        adjustments.saturation = 0.08
        return adjustments
    }
}
