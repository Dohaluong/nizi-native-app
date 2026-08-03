//
//  TripMiniCard.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI

/// Home's Trip rail card: a portrait, editorial cover with a centered trip title and the real
/// date range at its lower edge. The fixed canvas avoids inheriting a photo's intrinsic size.
struct TripMiniCard: View {
    let trip: TripSummary
    let assetProvider: PhotoAssetProvider
    @State private var coverImage: PlatformImage?
    static let cardWidth: CGFloat = 240
    static let cardHeight: CGFloat = 360
    private var cardHeight: CGFloat { Self.cardHeight }
    private var targetSize: CGSize { CGSize(width: Self.cardWidth * 2, height: cardHeight * 2) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: Self.cardWidth, height: cardHeight)
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.cardWidth, height: cardHeight)
                    .clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                .frame(width: Self.cardWidth, height: cardHeight)

            VStack(spacing: 3) {
                Text("A Trip to")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                Text(placeText)
                    .font(.onboardingSerif(size: 23, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(trip.dateRangeText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .frame(width: Self.cardWidth - 28)
            .padding(.bottom, 16)
        }
        .frame(width: Self.cardWidth, height: cardHeight, alignment: .bottom)
        // `scaledToFill` may render a landscape UIImage outside this canvas before clipping.
        // Explicitly bind the label's hit region to the visible card bounds.
        .contentShape(Rectangle())
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: trip.coverAssetID) { await loadCover() }
    }

    // Falls back to the classification label (never blank, never a raw enum name) for day trips
    // whose `primaryPlaceName` is nil because geocoding is skipped for them.
    private var placeText: String { trip.displayPlaceName ?? trip.classification.displayLabel }

    private func loadCover() async {
        guard let coverAssetID = trip.coverAssetID else { return }
        coverImage = assetProvider.cachedThumbnail(assetID: coverAssetID, targetSize: targetSize, contentMode: .fill)
        guard coverImage == nil else { return }
        do {
            // Editorial Trip covers remain sharp at their 180 × 270 display size, including
            // iCloud-backed photos. The request runs through the bounded background loader.
            coverImage = try await PhotoThumbnailRequestLoader.shared.thumbnail(
                assetID: coverAssetID,
                targetSize: targetSize
            )
        } catch {
            guard !(error is CancellationError) else { return }
            NiziLogger.discovery.error("trip_mini_card_cover_load_failed")
        }
    }
}

/// PhotoKit work for the Home Trip rail. This actor keeps synchronous PhotoKit asset lookup off
/// the UI actor and caps concurrent requests started by newly materialized cards.
/// `PhotoKitAssetProvider`'s app-session cache is shared, so results are
/// immediately available to the Home provider and every other viewer afterwards.
actor PhotoThumbnailRequestLoader {
    static let shared = PhotoThumbnailRequestLoader()
    /// Home card requests must never keep the first Memory Hero waiting.
    static let memoryHero = PhotoThumbnailRequestLoader(maximumConcurrentRequests: 1)
    /// A scrolling Memory gallery owns its own bounded lane rather than competing with Home.
    static let memoryGallery = PhotoThumbnailRequestLoader(maximumConcurrentRequests: 2)

    private let provider: PhotoAssetProvider = PhotoKitAssetProvider()
    private let maximumConcurrentRequests: Int
    private var activeRequestCount = 0
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []

    private init(maximumConcurrentRequests: Int = 2) {
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

    func thumbnail(
        assetID: String,
        targetSize: CGSize,
        contentMode: ThumbnailContentMode = .fill,
        networkAccessAllowed: Bool = true,
        deliveryMode: ThumbnailDeliveryMode = .highQuality
    ) async throws -> PlatformImage {
        await acquireSlot()
        defer { releaseSlot() }
        try Task.checkCancellation()

        return try await provider.requestThumbnail(
            assetID: assetID,
            targetSize: targetSize,
            networkAccessAllowed: networkAccessAllowed,
            deliveryMode: deliveryMode,
            contentMode: contentMode
        )
    }

    private func acquireSlot() async {
        if activeRequestCount < maximumConcurrentRequests {
            activeRequestCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    private func releaseSlot() {
        if let next = waitingContinuations.first {
            waitingContinuations.removeFirst()
            next.resume()
        } else {
            activeRequestCount -= 1
        }
    }
}
