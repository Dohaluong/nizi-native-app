//
//  AlbumPageCardView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// One Page rendered as a book-page card — real photos via `AlbumPageRenderer` +
/// `ProductionAlbumSlotPhotoProvider`. Shared by `AlbumDetailView`'s inline carousel and
/// `AlbumPageViewer`'s single-page Viewer so both present a Page identically.
struct AlbumPageCardView: View {
    let viewerPage: AlbumViewerPage
    let layoutRepository: AlbumLayoutRepository
    var onTapPhoto: ((AlbumPhotoAssignment) -> Void)? = nil
    /// § user request — drag-to-swap between two slots on this same Page. `nil` outside edit
    /// mode, same convention `onTapPhoto` already uses.
    var onSwapPhotos: ((_ from: AlbumPhotoAssignment, _ to: AlbumPhotoAssignment) -> Void)? = nil
    /// § user request — quick-tap to open the crop editor for a Page's photo. `nil` outside edit
    /// mode, same convention `onSwapPhotos` already uses.
    var onCropPhoto: ((_ assignment: AlbumPhotoAssignment, _ frameAspectRatio: CGFloat) -> Void)? = nil
    /// § user request — reports whenever a drag-to-swap is picked up/released, so the Viewer can
    /// lock page-turning out for the duration (see `AlbumPagingLockView`).
    var onDragActiveChanged: ((Bool) -> Void)? = nil

    var body: some View {
        Group {
            if let layout = try? layoutRepository.layout(id: viewerPage.page.layoutId) {
                AlbumPageRenderer(
                    layout: layout, assignments: viewerPage.page.assignments,
                    photoProvider: ProductionAlbumSlotPhotoProvider(),
                    onTapPhoto: onTapPhoto,
                    onSwapPhotos: onSwapPhotos,
                    onCropPhoto: onCropPhoto,
                    onDragActiveChanged: onDragActiveChanged
                )
            } else {
                Color(.secondarySystemFill)
            }
        }
        .padding(12)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
    }
}
