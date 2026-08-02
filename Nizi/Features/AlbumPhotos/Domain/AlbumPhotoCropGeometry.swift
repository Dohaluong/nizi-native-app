//
//  AlbumPhotoCropGeometry.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/2/26.
//

import CoreGraphics

/// The one place the "how does a photo fill its slot" rule lives — extracted from
/// `AlbumPhotoView` (Presentation, SwiftUI) so `PhotobookPageExportRenderer` (Application, Core
/// Graphics) can compute the exact same placement for PDF export without duplicating the formula.
/// Pure geometry, no `UIImage`/SwiftUI dependency — safe for both a live editor View and an
/// offline export pass to share.
enum AlbumPhotoCropGeometry {
    /// The size an `.aspectRatio(contentMode:)` image would render at within `frameSize` — `fill`
    /// covers `frameSize` entirely (one axis matches exactly, the other overflows); `!fill` (fit)
    /// stays fully inside it (one axis matches exactly, the other has empty space). Identical to
    /// `AlbumPhotoView`'s own former `aspectSize` — moved here verbatim, not reimplemented.
    static func aspectFitFillSize(imageSize: CGSize, frameSize: CGSize, fill: Bool) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, frameSize.width > 0, frameSize.height > 0 else {
            return frameSize
        }
        let imageAspect = imageSize.width / imageSize.height
        let frameAspect = frameSize.width / frameSize.height
        let imageIsRelativelyWider = imageAspect > frameAspect
        let widthMatchesFrame = fill ? !imageIsRelativelyWider : imageIsRelativelyWider
        if widthMatchesFrame {
            return CGSize(width: frameSize.width, height: frameSize.width / imageAspect)
        } else {
            return CGSize(width: frameSize.height * imageAspect, height: frameSize.height)
        }
    }

    /// The final rect — in frame-local coordinates, origin top-left — an image should be drawn at
    /// once `crop.scale`/`normalizedOffsetX`/`normalizedOffsetY` are applied on top of
    /// `aspectFitFillSize`'s base placement. Mathematically equivalent to what `AlbumPhotoView`
    /// achieves via `.frame(width:height:).offset(x:y:)` centered in a `frameSize`-sized parent
    /// frame (offset shifts the already-centered image; centering + offset together is exactly
    /// `frameCenter - scaledSize/2 + offset`) — verified against that view's modifier chain, not
    /// guessed. Callers that must not let the image paint outside the slot (every real call site
    /// except `AlbumPhotoCropSheet`'s own "show what panning further reveals" case) additionally
    /// clip to `CGRect(origin: .zero, size: frameSize)`.
    static func renderRect(imageSize: CGSize, frameSize: CGSize, fill: Bool, crop: AlbumPhotoCrop) -> CGRect {
        let baseSize = aspectFitFillSize(imageSize: imageSize, frameSize: frameSize, fill: fill)
        let scaledSize = CGSize(width: baseSize.width * crop.scale, height: baseSize.height * crop.scale)
        let centeredOrigin = CGPoint(
            x: (frameSize.width - scaledSize.width) / 2,
            y: (frameSize.height - scaledSize.height) / 2
        )
        let origin = CGPoint(
            x: centeredOrigin.x + crop.normalizedOffsetX * frameSize.width,
            y: centeredOrigin.y + crop.normalizedOffsetY * frameSize.height
        )
        return CGRect(origin: origin, size: scaledSize)
    }
}
