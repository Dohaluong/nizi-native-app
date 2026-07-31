//
//  AlbumPhotoPreviewView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Photos
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
    /// The Page this preview's `photos` belong to — needed (together with an assignment's own
    /// `slotId`) to call `AlbumEditActionApplying.apply(.removePhoto(pageId:slotId:), to:)` for
    /// the "Hide from Album" menu action.
    let pageId: String
    /// Memory reuses this proven viewer but edits must retain their Event source scope rather than
    /// pretending the photos belong to an Album.
    let editorSourceType: EditorSourceType
    /// "Hide from Album" is meaningful only for actual Album pages. Other callers (Memory) keep
    /// the viewer's zoom/info/edit experience without exposing that destructive-looking action.
    let allowsHidingPhotos: Bool
    let onDismiss: () -> Void
    /// Called after Photo Editor's Album "save as new asset" flow (`PhotoAssetExporting`) creates
    /// a brand-new `PHAsset` for the photo that used to be `oldPhotoId` — this view has no direct
    /// hold on the `AlbumDraft` itself, so `AlbumDetailView` (the actual owner) is responsible for
    /// swapping every reference to it (`AlbumEditActionApplying.replacePhoto`) and persisting the
    /// result. A no-op default so every other caller of this view is unaffected.
    var onPhotoReplaced: (_ oldPhotoId: String, _ newPhoto: AlbumPhotoReference) -> Void = { _, _ in }
    /// "Hide from Album" — removes just this one photo's assignment from its Page (never touches
    /// the Photos library itself, see § "album.photosRemainInLibrary"). § user request "chức năng
    /// xoá ảnh sẽ cho phép trang xoá hết ảnh" — removing a Page's last photo now succeeds (the
    /// Page becomes a blank "tap to add a photo" placeholder), so `false` here is only ever a
    /// genuine failure (e.g. the Page vanished from under this preview mid-edit), surfaced as its
    /// own generic alert rather than silently doing nothing.
    var onHidePhoto: (_ pageId: String, _ slotId: String) async -> Bool = { _, _ in false }

    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex: Int
    @State private var isZoomed = false
    @State private var verticalDragOffset: CGFloat = 0
    @State private var editorContext: EditorContext?
    @State private var currentPhotoDate: Date?
    @State private var showHideConfirmation = false
    @State private var hideBlockedAlert = false

    init(
        photos: [AlbumPhotoAssignment],
        albumId: String,
        allAlbumPhotoIds: [String],
        pageId: String,
        startIndex: Int,
        editorSourceType: EditorSourceType = .album,
        allowsHidingPhotos: Bool = true,
        onPhotoReplaced: @escaping (_ oldPhotoId: String, _ newPhoto: AlbumPhotoReference) -> Void = { _, _ in },
        onHidePhoto: @escaping (_ pageId: String, _ slotId: String) async -> Bool = { _, _ in false },
        onDismiss: @escaping () -> Void
    ) {
        self.photos = photos
        self.albumId = albumId
        self.allAlbumPhotoIds = allAlbumPhotoIds
        self.pageId = pageId
        self.editorSourceType = editorSourceType
        self.allowsHidingPhotos = allowsHidingPhotos
        self.onPhotoReplaced = onPhotoReplaced
        self.onHidePhoto = onHidePhoto
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: startIndex)
    }

    private var dismissProgress: CGFloat {
        min(abs(verticalDragOffset) / 400, 0.6)
    }

    var body: some View {
        ZStack(alignment: .top) {
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

            header
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task(id: currentIndex) {
            currentPhotoDate = await Self.fetchCreationDate(for: currentAssignment.photo)
        }
        .confirmationDialog(
            "album.photoPreview.hideConfirmTitle", isPresented: $showHideConfirmation, titleVisibility: .visible
        ) {
            Button("album.photoPreview.hideFromAlbum", role: .destructive) { hideCurrentPhoto() }
            Button("common.action.cancel", role: .cancel) {}
        } message: {
            Text("album.photosRemainInLibrary")
        }
        .alert("album.edit.remove_last_photo_title", isPresented: $hideBlockedAlert) {
            Button("common.action.cancel", role: .cancel) {}
        } message: {
            Text("album.edit.hide_photo_failed_message")
        }
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
                // A save swaps `photoId` out for a brand-new asset — this preview's `TabView` still
                // has the old (possibly now-deleted) photo loaded at `currentIndex`, so staying here
                // would show either a stale image or a broken one. Returning straight to the Album
                // is also just the more sensible place to land after "save this edit," rather than
                // back onto the single photo that was mid-edit a moment ago.
                if result.didSave {
                    onDismiss()
                }
            }
        }
    }

    private var currentAssignment: AlbumPhotoAssignment {
        photos[min(max(currentIndex, 0), photos.count - 1)]
    }

    /// X on the leading edge, this photo's capture date/time centered, "..." trailing — pinned
    /// close to the very top (§ layout request) rather than the old `.padding(.top, 54)` gap that
    /// used to sit under it; only the safe area itself (never ignored here, unlike the background)
    /// separates it from the notch/Dynamic Island.
    private var header: some View {
        HStack(spacing: 12) {
            closeButton
            Spacer()
            dateTimeInfo
            Spacer()
            moreOptionsMenu
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var dateTimeInfo: some View {
        if let currentPhotoDate {
            VStack(spacing: 2) {
                Text(Self.dayFormatted(currentPhotoDate))
                    .font(.system(size: 13, weight: .semibold))
                Text(Self.timeFormatted(currentPhotoDate))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
    }

    /// § 4.1 — opens Photo Editor on whichever photo is currently on screen, scoped to this whole
    /// Album (`allAlbumPhotoIds`), not just this Page's `photos`.
    private func openEditor() {
        guard photos.indices.contains(currentIndex) else { return }
        let photoId = photos[currentIndex].photo.sourceIdentifier
        editorContext = EditorContext(sourceType: editorSourceType, sourceId: albumId, photoId: photoId, photoIds: allAlbumPhotoIds)
    }

    private func hideCurrentPhoto() {
        guard photos.indices.contains(currentIndex) else { return }
        let slotId = photos[currentIndex].slotId
        Task {
            let succeeded = await onHidePhoto(pageId, slotId)
            if succeeded {
                onDismiss()
            } else {
                hideBlockedAlert = true
            }
        }
    }

    /// Replaces the old standalone Edit button — "Edit Photo" and "Hide from Album" (§ layout
    /// request) live together behind one "..." menu instead, matching `AlbumDetailView.
    /// albumOptionsMenu`'s own `Menu`/`ellipsis` convention.
    private var moreOptionsMenu: some View {
        Menu {
            Button { openEditor() } label: {
                Label("album.photoPreview.editPhoto", systemImage: "wand.and.stars")
            }
            if allowsHidingPhotos {
                Button(role: .destructive) { showHideConfirmation = true } label: {
                    Label("album.photoPreview.hideFromAlbum", systemImage: "eye.slash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private static func fetchCreationDate(for photo: AlbumPhotoReference) async -> Date? {
        guard photo.source == .applePhotos else { return nil }
        return await PHAssetRepository().asset(localIdentifier: photo.sourceIdentifier)?.creationDate
    }

    private static func dayFormatted(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    private static func timeFormatted(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
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
