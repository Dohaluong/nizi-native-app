//
//  AlbumPhotoCropSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import SwiftUI

/// Bundles an assignment with the on-screen aspect ratio of the slot it's currently shown in, and
/// which Page it's on — `AlbumPageRenderer` already has the exact ratio (`rect.width / rect.height`,
/// post `scaleX`/`scaleY`) by the time a tap fires, and it can differ slightly from `slot.frame`'s
/// own raw ratio on a non-uniformly-scaled canvas, so it's passed through rather than recomputed
/// here; `pageId` is what `AlbumEditAction.removePhoto` needs alongside the assignment's own
/// `slotId`.
struct AlbumPhotoCropTarget: Identifiable, Hashable {
    let assignment: AlbumPhotoAssignment
    let frameAspectRatio: CGFloat
    let pageId: String
    /// § user request — "trang bìa sẽ có cấu trúc như trang ruột ... crop ảnh tương tự như trang
    /// khác": the cover photo isn't a real `AlbumPhotoAssignment` living in `draft.spreads` (see
    /// `AlbumPageViewer.coverAsViewerPage`), so its own crop screen dispatches to
    /// `AlbumEditAction.updateCoverPhotoCrop`/`.changeCover` instead of `.updatePhotoCrop`/
    /// `.assignPhoto` — this flag is what `AlbumPageViewer.cropDestination` branches on.
    var isCoverPhoto: Bool = false
    var id: String { assignment.id }
}

/// § user request — quick-tap a photo to open this: pinch to zoom, drag to pan, matching how it
/// fills its own slot in the Album; a "Xóa ảnh" button to remove it from the Page; a "Đổi ảnh"
/// button to replace it with a different photo already in the Album (opens the same picker
/// "đổi ảnh bìa" already uses).
///
/// § user report — this used to be a `.sheet`, which has its own interactive drag-to-dismiss that
/// fought with panning the photo (dragging down past the pan limit closed the whole screen instead
/// of just stopping). Pushed via `AlbumPageViewer`'s own `NavigationStack`
/// (`.navigationDestination(item:)`) instead — a real screen, not a modal, so there's no competing
/// dismiss gesture at all.
///
/// Crop editing only ever touches `AlbumPhotoAssignment.crop` (scale + normalized offset) — the
/// same two fields `AlbumPhotoView` already reads to render every slot everywhere else in the app,
/// so this screen reuses that exact view for its own live preview instead of re-deriving the crop
/// math, guaranteeing the preview matches the real Page pixel-for-pixel. Never touches the
/// underlying `AlbumPhotoReference` or the original asset (§ "không crop ảnh thực tế, không ảnh
/// hưởng đến ảnh gốc").
struct AlbumPhotoCropSheet: View {
    let assignment: AlbumPhotoAssignment
    let frameAspectRatio: CGFloat
    /// Only for `AlbumPhotoPickerSheet`'s own "which photos are already in this Album" list (§
    /// "đổi ảnh ... như phần đổi ảnh bìa") — never mutated directly here.
    let draft: AlbumDraft
    let onSave: (AlbumPhotoCrop) -> Void
    let onCancel: () -> Void
    /// § user request — the cover photo always needs exactly one photo (there's no "empty slot"
    /// state for it the way a content Page's slot has), so its own crop screen has no "Xóa ảnh"
    /// button at all — `nil` hides `bottomActionButton`'s remove action entirely instead of
    /// wiring it to something that doesn't make sense.
    let onRemove: (() -> Void)?
    let onChangePhoto: (AlbumPhotoReference) -> Void

    @State private var scale: CGFloat
    @State private var lastScale: CGFloat
    /// Normalized (frame-size-independent) offset, the same unit `AlbumPhotoCrop.normalizedOffsetX/Y`
    /// already uses — kept in this unit throughout (never raw points) so it doesn't need to be
    /// re-derived once this sheet's own `GeometryReader` settles on its frame's actual point size.
    @State private var normalizedOffset: CGSize
    @State private var lastNormalizedOffset: CGSize
    /// § user report — "nếu fit chiều cao thì không pan hết chiều ngang được": `nil` until the real
    /// photo loads and reports its own pixel size, used by `clampedOffset` below. See its own doc
    /// comment for why the frame's aspect ratio alone isn't enough.
    @State private var imageAspectRatio: CGFloat?
    @State private var isPickingPhoto = false

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 5
    private static let framePadding: CGFloat = 24

    init(
        assignment: AlbumPhotoAssignment, frameAspectRatio: CGFloat, draft: AlbumDraft,
        onSave: @escaping (AlbumPhotoCrop) -> Void, onCancel: @escaping () -> Void,
        onRemove: (() -> Void)? = nil, onChangePhoto: @escaping (AlbumPhotoReference) -> Void
    ) {
        self.assignment = assignment
        self.frameAspectRatio = frameAspectRatio
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
        self.onRemove = onRemove
        self.onChangePhoto = onChangePhoto
        let crop = assignment.crop
        _scale = State(initialValue: crop.scale)
        _lastScale = State(initialValue: crop.scale)
        let startOffset = CGSize(width: crop.normalizedOffsetX, height: crop.normalizedOffsetY)
        _normalizedOffset = State(initialValue: startOffset)
        _lastNormalizedOffset = State(initialValue: startOffset)
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let frameSize = Self.frameSize(fitting: canvasSize, aspectRatio: frameAspectRatio)
            let frameRect = CGRect(
                x: (canvasSize.width - frameSize.width) / 2,
                y: (canvasSize.height - frameSize.height) / 2,
                width: frameSize.width,
                height: frameSize.height
            )
            ZStack {
                Color.black.ignoresSafeArea()
                cropCanvas(canvasSize: canvasSize, frameRect: frameRect)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("album.crop.title")
        .navigationBarTitleDisplayMode(.inline)
        // A pushed screen already gets a system back chevron for free — hidden here so there's
        // only ever one obvious way back (our own Cancel button), not two.
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.action.cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("album.crop.done") {
                    onSave(AlbumPhotoCrop(normalizedOffsetX: normalizedOffset.width, normalizedOffsetY: normalizedOffset.height, scale: scale))
                }
                .fontWeight(.semibold)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .sheet(isPresented: $isPickingPhoto) {
            AlbumPhotoPickerSheet(draft: draft, title: "album.crop.changePhoto") { reference in
                isPickingPhoto = false
                onChangePhoto(reference)
            }
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 0) {
            if let onRemove {
                bottomActionButton("album.removePhoto", systemImage: "minus.circle", role: .destructive, action: onRemove)
            }
            bottomActionButton("album.crop.changePhoto", systemImage: "photo.on.rectangle") { isPickingPhoto = true }
        }
        .padding(.vertical, 8)
        .background(Color.black)
    }

    private func bottomActionButton(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                Text(titleKey).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .tint(role == .destructive ? .red : .white)
    }

    /// § user request — "Ảnh cần hiển thị cả phía bên ngoài khung crop nhưng màu nền tối hơn": the
    /// photo itself is rendered `clipsToFrame: false` (still sized/positioned exactly as it would
    /// be inside just the frame — same crop math, same `frameRect` origin — but no longer cut off
    /// at that boundary), so panning reveals what's actually there beyond the frame instead of
    /// cutting to black. `CropDimOverlay` then darkens everything *except* `frameRect` on top of
    /// it, and gestures are attached to the whole canvas (not just the frame) so touching the
    /// dimmed surrounding area still pans/zooms — it's the same live photo, just dimmed.
    private func cropCanvas(canvasSize: CGSize, frameRect: CGRect) -> some View {
        let liveCrop = AlbumPhotoCrop(normalizedOffsetX: normalizedOffset.width, normalizedOffsetY: normalizedOffset.height, scale: scale)
        return ZStack {
            AlbumPhotoView(
                reference: assignment.photo, crop: liveCrop, contentMode: .fill, targetSize: nil,
                clipsToFrame: false,
                onImageSizeChanged: { size in
                    guard size.width > 0, size.height > 0 else { return }
                    imageAspectRatio = size.width / size.height
                }
            )
            .frame(width: frameRect.width, height: frameRect.height)
            .position(x: frameRect.midX, y: frameRect.midY)

            CropDimOverlay(holeRect: frameRect)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: frameRect.width, height: frameRect.height)
                .position(x: frameRect.midX, y: frameRect.midY)
                .allowsHitTesting(false)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .contentShape(Rectangle())
        .clipped()
        // § "Cho phép dùng 2 ngón zoom ảnh, pan ảnh" — pinch to zoom (its own gesture) and drag
        // to pan (attached `.simultaneously`, so a plain one-finger drag pans without needing a
        // pinch at the same time, and both still update together during an actual two-finger
        // pinch-and-drag).
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let newScale = Self.clampedScale(lastScale * value)
                    scale = newScale
                    normalizedOffset = clampedOffset(normalizedOffset, scale: newScale)
                }
                .onEnded { _ in
                    lastScale = scale
                    lastNormalizedOffset = normalizedOffset
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    let delta = CGSize(
                        width: value.translation.width / frameRect.width,
                        height: value.translation.height / frameRect.height
                    )
                    let proposed = CGSize(
                        width: lastNormalizedOffset.width + delta.width,
                        height: lastNormalizedOffset.height + delta.height
                    )
                    normalizedOffset = clampedOffset(proposed, scale: scale)
                }
                .onEnded { _ in
                    lastNormalizedOffset = normalizedOffset
                }
        )
    }

    private static func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    /// § user report — "nếu fit chiều cao thì không pan hết chiều ngang được ... còn cách 1 đoạn":
    /// `.aspectRatio(contentMode: .fill)` only makes ONE axis (whichever is the tighter constraint
    /// for *this specific photo's* own dimensions vs the frame's) land exactly on the frame size at
    /// `scale == 1` — the other axis already overflows the frame before `scale` is applied at all,
    /// by a ratio that depends on the photo's real aspect ratio, not the frame's. The previous
    /// `(scale - 1) / 2` bound (same in both axes) assumed zero overflow in *both*, which
    /// under-clamped the non-constraining axis and left an un-reachable gap right at its edges.
    /// `imageAspectRatio / frameAspectRatio` tells the two axes apart: whichever is "wider" than the
    /// frame overflows horizontally by that ratio (vertically matches exactly), and vice versa.
    private func clampedOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        let overflow = Self.overflowRatio(imageAspectRatio: imageAspectRatio, frameAspectRatio: frameAspectRatio)
        let maxOffsetX = (overflow.width * scale - 1) / 2
        let maxOffsetY = (overflow.height * scale - 1) / 2
        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    /// How much the photo, at `scale == 1`, already overflows the frame in each axis — `1` means
    /// "lands exactly on the frame size, zero overflow, zero room to pan" (true for whichever axis
    /// is the tighter constraint, and true in both axes when the photo's own ratio happens to match
    /// the frame's exactly). Before the real photo has loaded (`imageAspectRatio == nil`), falls
    /// back to `(1, 1)` — the same (over-)restrictive assumption the old code always made, safe
    /// because it can only ever be *too tight*, never wrong in a way that reveals a gap.
    private static func overflowRatio(imageAspectRatio: CGFloat?, frameAspectRatio: CGFloat) -> CGSize {
        guard let imageAspectRatio, imageAspectRatio > 0, frameAspectRatio > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let ratio = imageAspectRatio / frameAspectRatio
        return ratio >= 1 ? CGSize(width: ratio, height: 1) : CGSize(width: 1, height: 1 / ratio)
    }

    private static func frameSize(fitting available: CGSize, aspectRatio: CGFloat) -> CGSize {
        let maxWidth = available.width - framePadding * 2
        let maxHeight = available.height - framePadding * 2
        guard aspectRatio > 0, maxWidth > 0, maxHeight > 0 else { return available }
        if maxWidth / aspectRatio <= maxHeight {
            return CGSize(width: maxWidth, height: maxWidth / aspectRatio)
        } else {
            return CGSize(width: maxHeight * aspectRatio, height: maxHeight)
        }
    }
}

/// The full canvas rect minus `holeRect`, filled with an even-odd rule — darkens everywhere
/// *except* the crop frame without needing `.mask()` (that's for punching a hole in existing
/// content to reveal what's underneath; here the dimming color itself is the only content, so
/// filling the compound path directly is simpler).
private struct CropDimOverlay: Shape {
    let holeRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(holeRect)
        return path
    }
}
