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
    /// § user request — quick-tap to edit a text block's real content and style. `nil` outside
    /// edit mode, same convention `onCropPhoto` already uses.
    var onTapTextBlock: ((_ effective: AlbumTextAssignment, _ kind: AlbumTextBlockKind) -> Void)? = nil
    /// § user request — "Thêm trang ... Click vào có thể thêm ảnh sau": tapping a blank Page
    /// (`AlbumDraftPage.isBlank`) instead of one of its slots — there are none to tap. `nil`
    /// outside edit mode, same convention every other callback here already uses.
    var onTapBlankPage: (() -> Void)? = nil

    var body: some View {
        Group {
            if let layout = try? layoutRepository.layout(id: viewerPage.page.layoutId) {
                AlbumPageRenderer(
                    layout: layout, assignments: viewerPage.page.assignments,
                    textAssignments: viewerPage.page.textAssignments,
                    photoProvider: ProductionAlbumSlotPhotoProvider(),
                    onTapPhoto: onTapPhoto,
                    onSwapPhotos: onSwapPhotos,
                    onCropPhoto: onCropPhoto,
                    onDragActiveChanged: onDragActiveChanged,
                    onTapTextBlock: onTapTextBlock
                )
            } else if viewerPage.page.isBlank {
                blankPagePlaceholder
            } else {
                Color(.secondarySystemFill)
            }
        }
        // § user report — "tất cả các trang ... đều có 1 dải bleed, trong khi layout mẫu có nhiều
        // mẫu ảnh full viền": this `.padding(12)` used to inset *every* Page's rendered content by
        // a fixed 12pt regardless of what its own layout actually specifies — the Layout Studio's
        // own swatch preview never had this (it renders `AlbumPageRenderer` directly, no card
        // wrapper), which is why swatches always looked correctly full-bleed while the real Page
        // never did. Removed so a layout with `cornerRadius: 0` on a full-bleed slot renders truly
        // edge-to-edge here too — the outer card's own corner rounding stays (§ "ngoại trừ phần
        // border-radius vẫn giữ").
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    private var blankPagePlaceholder: some View {
        Button {
            onTapBlankPage?()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 34, weight: .light))
                Text("album.addPhoto")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // § user report — "phần nền trang màu xám chìm vào nền chung, cần chuyển thành nền
            // trắng": this filled the whole card, hiding the outer `.background(Color.white)`
            // below entirely — a gray-on-gray placeholder blended straight into the screen's own
            // `.systemGroupedBackground` instead of reading as a distinct Page card.
            .background(Color.white)
        }
        .buttonStyle(.plain)
        .disabled(onTapBlankPage == nil)
    }
}
