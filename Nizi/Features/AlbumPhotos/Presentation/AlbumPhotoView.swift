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
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
                .scaleEffect(crop.scale)
                .offset(x: crop.normalizedOffsetX * proxy.size.width, y: crop.normalizedOffsetY * proxy.size.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
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
        }
    }
}
