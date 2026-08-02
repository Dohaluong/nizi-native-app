//
//  AlbumPhotoView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

private struct AlbumPhotoProviderKey: EnvironmentKey {
    static let defaultValue: any AlbumPhotoProviding = MockAlbumPhotoProvider()
}

extension EnvironmentValues {
    var albumPhotoProvider: any AlbumPhotoProviding {
        get { self[AlbumPhotoProviderKey.self] }
        set { self[AlbumPhotoProviderKey.self] = newValue }
    }
}

/// Renders one photo end to end — loading/degraded/success/missing/failure — driven by whatever
/// `AlbumPhotoProviding` is in the environment (`ApplePhotosAlbumPhotoProvider` in production,
/// `MockAlbumPhotoProvider` in Previews/tests). See docs/specs/SPEC-REAL-ALBUM.md § 10.
struct AlbumPhotoView: View {
    let reference: AlbumPhotoReference
    let crop: AlbumPhotoCrop
    let contentMode: AlbumPhotoContentMode
    /// Pixel size to request. When `nil`, this view measures its own point size via
    /// `GeometryReader` and multiplies by the screen scale — the explicit-size path (used by
    /// `AlbumPageRenderer`'s bridge) is preferred so this doesn't need its own `GeometryReader`
    /// nested inside the renderer's.
    let targetSize: CGSize?
    /// § user request — `AlbumPhotoCropSheet` needs the photo to keep rendering *past* its own
    /// frame (dimmed by an overlay outside the crop rect) instead of being cut off at it, so the
    /// user can see what panning further would bring into frame. `true` everywhere else (every
    /// real Page slot, every preview/swatch) — those all still want the normal "clip to my own
    /// bounds" behavior, unchanged.
    var clipsToFrame: Bool = true
    /// § user report — `AlbumPhotoCropSheet`'s pan clamp needs the photo's own real aspect ratio,
    /// not just the frame's: `.aspectRatio(contentMode: .fill)` only makes ONE axis match the
    /// frame exactly (whichever axis is the tighter constraint for *this specific photo's*
    /// dimensions) — the other axis already overflows the frame even before `crop.scale` is
    /// applied, by an amount that depends entirely on the photo's own pixel dimensions, which
    /// nothing outside this view (still loading the image asynchronously) has access to otherwise.
    /// Reported once per newly-loaded image; `nil` everywhere else, so unused.
    var onImageSizeChanged: ((CGSize) -> Void)? = nil

    @Environment(\.albumPhotoProvider) private var provider
    @State private var state: AlbumPhotoLoadState = .idle

    var body: some View {
        if let targetSize {
            content(pixelSize: targetSize)
                .task(id: requestKey(pixelSize: targetSize)) {
                    await load(pixelSize: targetSize)
                }
        } else {
            GeometryReader { proxy in
                let pixelSize = CGSize(width: proxy.size.width * UIScreen.main.scale, height: proxy.size.height * UIScreen.main.scale)
                content(pixelSize: pixelSize)
                    .task(id: requestKey(pixelSize: pixelSize)) {
                        await load(pixelSize: pixelSize)
                    }
            }
        }
    }

    private func requestKey(pixelSize: CGSize) -> String {
        "\(reference.sourceIdentifier)-\(Int(pixelSize.width))x\(Int(pixelSize.height))-\(contentMode.rawValue)"
    }

    @ViewBuilder
    private func content(pixelSize: CGSize) -> some View {
        switch state {
        case .idle, .loading:
            loadingView
        case let .degraded(image):
            imageView(image, pixelSize: pixelSize)
        case let .success(image):
            imageView(image, pixelSize: pixelSize)
                .transition(.opacity)
        case .missing:
            missingView
        case let .failure(error):
            failureView(error)
        }
    }

    private var loadingView: some View {
        ZStack {
            Color(.secondarySystemFill)
            ProgressView()
        }
    }

    private func imageView(_ image: PlatformImage, pixelSize: CGSize) -> some View {
        GeometryReader { proxy in
            // § user report — "chạm vào phần zoom vô hình của ảnh crop sẽ vào trong ảnh crop chứ
            // không vào ảnh của khung mới cần sửa" / "khoảng tác động bị ảnh hưởng sang frame
            // khác tương ứng với diện tích ảnh phóng to": this used to be `.scaleEffect(crop
            // .scale)` — a *render transform*, which visually enlarges a view without shrinking
            // its interactive/hit-test bounds back down to match. `.clipped()` only clips what's
            // *drawn*; adding `.contentShape(Rectangle())` on top wasn't enough to override it
            // either — the zoomed-in photo's invisible overflow kept staying tappable well past
            // its own slot, into whichever neighbor it visually overlapped, by exactly the
            // zoomed-in amount. Computing the scaled-up size as a real `.frame()` instead (via
            // `Self.aspectFillSize`) sidesteps the whole transform-vs-hit-test-bounds mismatch:
            // an explicitly-sized, then `.clipped()`, view has no separate "hit-test size" to
            // ever disagree with its rendered size in the first place.
            let baseFillSize = AlbumPhotoCropGeometry.aspectFitFillSize(imageSize: image.size, frameSize: proxy.size, fill: contentMode == .fill)
            let content = Image(uiImage: image)
                .resizable()
                .frame(width: baseFillSize.width * crop.scale, height: baseFillSize.height * crop.scale)
                .offset(x: crop.normalizedOffsetX * proxy.size.width, y: crop.normalizedOffsetY * proxy.size.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
            if clipsToFrame {
                content.clipped().contentShape(Rectangle())
            } else {
                content
            }
        }
    }

    private var missingView: some View {
        ZStack {
            Color(.secondarySystemFill)
            VStack(spacing: 6) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                Text("album.photoUnavailable")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func failureView(_ error: AlbumPhotoProviderError) -> some View {
        ZStack {
            Color(.secondarySystemFill)
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                Text("album.unableToLoadPhoto")
                    .font(.caption2)
                Button("album.retry") {
                    Task { await load(pixelSize: targetSize ?? CGSize(width: 400, height: 400)) }
                }
                .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func load(pixelSize: CGSize) async {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }
        state = .loading
        let request = AlbumPhotoRequest(reference: reference, targetPixelSize: pixelSize, contentMode: contentMode, deliveryMode: .opportunistic)
        for await newState in provider.loadImage(request: request) {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.15)) {
                state = newState
            }
            switch newState {
            case let .degraded(image), let .success(image):
                onImageSizeChanged?(image.size)
            default:
                break
            }
        }
    }
}
