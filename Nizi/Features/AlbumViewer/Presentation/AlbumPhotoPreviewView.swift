//
//  AlbumPhotoPreviewView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Full-screen zoomed preview for the photos on one Page, tapped inside `AlbumDetailView`'s Page
/// carousel — scoped to that Page's own photos only, never the whole Album.
///
/// This mirrors the proven pattern from `EventDetailView.swift`'s `CurationPreviewView` /
/// `CurationPreviewPage` (the app's other full-screen photo viewer) rather than the hand-rolled
/// `DragGesture`-driven pager this file used before, which kept producing stutter and gesture
/// conflicts. The key differences from the old approach:
/// - Paging between photos is a native `TabView(.page)`, not a manually offset `HStack` — this
///   gets correct rubber-banding, velocity, and interruption handling from the platform instead
///   of hand-computed offset/threshold math.
/// - Pan-while-zoomed uses `.highPriorityGesture(_, including:)` with a mask that's `.all` only
///   while `scale > 1` and `.none` at rest — so it only steals touches from `TabView`'s own
///   paging gesture while actually zoomed in, instead of the two competing via a always-active
///   `.simultaneousGesture`.
struct AlbumPhotoPreviewView: View {
    let photos: [AlbumPhotoAssignment]
    /// This Album's own id and every photo in it (not just this Page's `photos`) — threaded
    /// through so the `Edit` entry point below can build a real `EditorContext` (PHOTO-EDITOR.md
    /// § 4.1). `AlbumDetailView` is the only caller and already has both on hand.
    let albumId: String
    let allAlbumPhotoIds: [String]
    let onDismiss: () -> Void
    /// Called after Photo Editor's Album "save as new asset" flow (`PhotoAssetExporting`) creates
    /// a brand-new `PHAsset` for the photo that used to be `oldPhotoId` — this view has no direct
    /// hold on the `AlbumDraft` itself, so `AlbumDetailView` (the actual owner) is responsible for
    /// swapping every reference to it (`AlbumEditActionApplying.replacePhoto`) and persisting the
    /// result. A no-op default so every other caller of this view is unaffected.
    var onPhotoReplaced: (_ oldPhotoId: String, _ newPhoto: AlbumPhotoReference) -> Void = { _, _ in }

    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex: Int
    @State private var isZoomed = false
    @State private var verticalDragOffset: CGFloat = 0
    @State private var editorContext: EditorContext?

    init(
        photos: [AlbumPhotoAssignment],
        albumId: String,
        allAlbumPhotoIds: [String],
        startIndex: Int,
        onPhotoReplaced: @escaping (_ oldPhotoId: String, _ newPhoto: AlbumPhotoReference) -> Void = { _, _ in },
        onDismiss: @escaping () -> Void
    ) {
        self.photos = photos
        self.albumId = albumId
        self.allAlbumPhotoIds = allAlbumPhotoIds
        self.onPhotoReplaced = onPhotoReplaced
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: startIndex)
    }

    private var dismissProgress: CGFloat {
        min(abs(verticalDragOffset) / 400, 0.6)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, assignment in
                    AlbumPhotoPreviewPage(assignment: assignment, isActive: index == currentIndex) { zoomed in
                        isZoomed = zoomed
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: verticalDragOffset)
            .opacity(1 - dismissProgress)
            .gesture(verticalDismissGesture)

            HStack(spacing: 10) {
                editButton
                closeButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 54)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .fullScreenCover(item: $editorContext) { context in
            PhotoEditorView(
                context: context,
                repository: SwiftDataPhotoEditRepository(modelContainer: modelContext.container),
                presetRepository: CustomizablePresetRepository(modelContainer: modelContext.container),
                collectionStyleRepository: SwiftDataCollectionStyleRepository(modelContainer: modelContext.container)
            ) { result in
                // Album's save flow always exports a brand-new asset (`PhotoAssetExporting`), never
                // just a recipe — `newPhotoId` is how the caller learns what to swap `photoId`'s
                // references over to.
                if let newPhotoId = result.newPhotoId {
                    let newReference = AlbumPhotoReference(
                        id: newPhotoId, source: .applePhotos, sourceIdentifier: newPhotoId, originalFilename: nil
                    )
                    onPhotoReplaced(result.photoId, newReference)
                }
                editorContext = nil
            }
        }
    }

    /// § 4.1 — opens Photo Editor on whichever photo is currently on screen, scoped to this whole
    /// Album (`allAlbumPhotoIds`), not just this Page's `photos`.
    private var editButton: some View {
        Button {
            guard photos.indices.contains(currentIndex) else { return }
            let photoId = photos[currentIndex].photo.sourceIdentifier
            editorContext = EditorContext(sourceType: .album, sourceId: albumId, photoId: photoId, photoIds: allAlbumPhotoIds)
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("photoEditor.editButton.accessibilityLabel"))
    }

    /// Vertical-only, gated by `isZoomed` so it can never fire while the user is panning around a
    /// zoomed photo, and by "vertical translation dominates" so it never fights `TabView`'s own
    /// horizontal paging gesture.
    private var verticalDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isZoomed else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                verticalDragOffset = value.translation.height
            }
            .onEnded { value in
                guard !isZoomed else { return }
                let isVertical = abs(value.translation.height) > abs(value.translation.width)
                if isVertical, abs(value.translation.height) > 120 {
                    onDismiss()
                } else {
                    withAnimation(.spring(duration: 0.25)) { verticalDragOffset = 0 }
                }
            }
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// One photo's pinch-to-zoom / double-tap-to-zoom / pan-while-zoomed — the per-page counterpart
/// to `EventDetailView.CurationPreviewPage`, adapted to load through `AlbumPhotoView` (this
/// feature's photo pipeline) instead of a raw cached `PlatformImage`.
private struct AlbumPhotoPreviewPage: View {
    let assignment: AlbumPhotoAssignment
    let isActive: Bool
    let onZoomChanged: (Bool) -> Void

    @State private var scale: CGFloat = 1
    @State private var pinchStartScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { proxy in
            AlbumPhotoView(reference: assignment.photo, crop: .centered, contentMode: .fit, targetSize: nil)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(magnifyGesture(containerSize: proxy.size))
                // Only claims the touch (blocking TabView's paging) while actually zoomed in —
                // at 1x this participates as `.none`, so swipe-between-photos is untouched.
                .highPriorityGesture(
                    panGesture(containerSize: proxy.size),
                    including: scale > minScale ? .all : .none
                )
                .onTapGesture(count: 2) { toggleDoubleTapZoom() }
        }
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            resetZoom()
        }
    }

    private func magnifyGesture(containerSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = min(maxScale, max(minScale, pinchStartScale * value.magnification))
                scale = newScale
                offset = clampedOffset(offset, scale: newScale, containerSize: containerSize)
                onZoomChanged(scale > minScale)
            }
            .onEnded { _ in
                pinchStartScale = scale
                dragStartOffset = offset
                if scale <= minScale {
                    withAnimation(.spring(duration: 0.2)) { resetZoom() }
                }
            }
    }

    private func panGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard scale > minScale else { return }
                let candidate = CGSize(
                    width: dragStartOffset.width + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
                offset = clampedOffset(candidate, scale: scale, containerSize: containerSize)
            }
            .onEnded { _ in
                dragStartOffset = offset
            }
    }

    private func toggleDoubleTapZoom() {
        withAnimation(.spring(duration: 0.25)) {
            if scale > minScale {
                resetZoom()
            } else {
                scale = doubleTapScale
                pinchStartScale = doubleTapScale
                onZoomChanged(true)
            }
        }
    }

    private func resetZoom() {
        scale = minScale
        pinchStartScale = minScale
        offset = .zero
        dragStartOffset = .zero
        onZoomChanged(false)
    }

    /// Keeps the zoomed image from panning past its own edge — standard "can't drag the photo
    /// off screen" clamp, assuming the image is centered and scaled about its own center.
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat, containerSize: CGSize) -> CGSize {
        let maxX = max(0, (containerSize.width * (scale - 1)) / 2)
        let maxY = max(0, (containerSize.height * (scale - 1)) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
