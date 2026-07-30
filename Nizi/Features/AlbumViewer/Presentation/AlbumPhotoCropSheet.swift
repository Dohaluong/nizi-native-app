//
//  AlbumPhotoCropSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import SwiftUI

/// Bundles an assignment with the on-screen aspect ratio of the slot it's currently shown in —
/// `AlbumPageRenderer` already has that exact ratio (`rect.width / rect.height`, post `scaleX`/
/// `scaleY`) by the time a tap fires, and it can differ slightly from `slot.frame`'s own raw ratio
/// on a non-uniformly-scaled canvas, so it's passed through rather than recomputed here.
struct AlbumPhotoCropTarget: Identifiable {
    let assignment: AlbumPhotoAssignment
    let frameAspectRatio: CGFloat
    var id: String { assignment.id }
}

/// § user request — quick-tap a photo to open this: pinch to zoom, drag to pan, matching how it
/// fills its own slot in the Album. Only ever edits `AlbumPhotoAssignment.crop` (scale + normalized
/// offset) — the same two fields `AlbumPhotoView` already reads to render every slot everywhere
/// else in the app, so this sheet reuses that exact view for its own live preview instead of
/// re-deriving the crop math, guaranteeing the preview matches the real Page pixel-for-pixel.
/// Never touches the underlying `AlbumPhotoReference` or the original asset (§ "không crop ảnh
/// thực tế, không ảnh hưởng đến ảnh gốc").
struct AlbumPhotoCropSheet: View {
    let assignment: AlbumPhotoAssignment
    let frameAspectRatio: CGFloat
    let onSave: (AlbumPhotoCrop) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat
    @State private var lastScale: CGFloat
    /// Normalized (frame-size-independent) offset, the same unit `AlbumPhotoCrop.normalizedOffsetX/Y`
    /// already uses — kept in this unit throughout (never raw points) so it doesn't need to be
    /// re-derived once this sheet's own `GeometryReader` settles on its frame's actual point size.
    @State private var normalizedOffset: CGSize
    @State private var lastNormalizedOffset: CGSize

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 5
    private static let framePadding: CGFloat = 24

    init(assignment: AlbumPhotoAssignment, frameAspectRatio: CGFloat, onSave: @escaping (AlbumPhotoCrop) -> Void, onCancel: @escaping () -> Void) {
        self.assignment = assignment
        self.frameAspectRatio = frameAspectRatio
        self.onSave = onSave
        self.onCancel = onCancel
        let crop = assignment.crop
        _scale = State(initialValue: crop.scale)
        _lastScale = State(initialValue: crop.scale)
        let startOffset = CGSize(width: crop.normalizedOffsetX, height: crop.normalizedOffsetY)
        _normalizedOffset = State(initialValue: startOffset)
        _lastNormalizedOffset = State(initialValue: startOffset)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let frameSize = Self.frameSize(fitting: proxy.size, aspectRatio: frameAspectRatio)
                ZStack {
                    Color.black.ignoresSafeArea()
                    cropCanvas(frameSize: frameSize)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .navigationTitle("album.crop.title")
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }

    private func cropCanvas(frameSize: CGSize) -> some View {
        let liveCrop = AlbumPhotoCrop(normalizedOffsetX: normalizedOffset.width, normalizedOffsetY: normalizedOffset.height, scale: scale)
        return AlbumPhotoView(reference: assignment.photo, crop: liveCrop, contentMode: .fill, targetSize: nil)
            .frame(width: frameSize.width, height: frameSize.height)
            .clipShape(Rectangle())
            .overlay(Rectangle().stroke(Color.white, lineWidth: 2))
            .contentShape(Rectangle())
            // § "Cho phép dùng 2 ngón zoom ảnh, pan ảnh" — pinch to zoom (its own gesture) and drag
            // to pan (attached `.simultaneously`, so a plain one-finger drag pans without needing a
            // pinch at the same time, and both still update together during an actual two-finger
            // pinch-and-drag).
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = Self.clampedScale(lastScale * value)
                        scale = newScale
                        normalizedOffset = Self.clampedOffset(normalizedOffset, scale: newScale)
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
                            width: value.translation.width / frameSize.width,
                            height: value.translation.height / frameSize.height
                        )
                        let proposed = CGSize(
                            width: lastNormalizedOffset.width + delta.width,
                            height: lastNormalizedOffset.height + delta.height
                        )
                        normalizedOffset = Self.clampedOffset(proposed, scale: scale)
                    }
                    .onEnded { _ in
                        lastNormalizedOffset = normalizedOffset
                    }
            )
    }

    private static func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    /// § user request — "Không cho các cạnh ảnh nhỏ hơn các cạnh frame": at `scale == 1` the photo
    /// (rendered `.aspectRatio(contentMode: .fill)`, same as every other slot) already exactly
    /// covers the frame with zero room to pan; at any `scale`, the rendered photo is `scale` times
    /// the frame's own size in each axis, so panning by more than half the extra size in that axis
    /// would pull an edge inside the frame and reveal a gap. Expressed as a normalized fraction of
    /// the frame's own size (so it holds regardless of the frame's actual point size),
    /// that bound is `(scale - 1) / 2`.
    private static func clampedOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        let maxOffset = (scale - 1) / 2
        return CGSize(
            width: min(max(offset.width, -maxOffset), maxOffset),
            height: min(max(offset.height, -maxOffset), maxOffset)
        )
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
