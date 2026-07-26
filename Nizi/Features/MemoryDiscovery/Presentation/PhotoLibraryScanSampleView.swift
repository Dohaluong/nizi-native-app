//
//  PhotoLibraryScanSampleView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI

/// Debug-only screen: metadata scan summary + a scrollable sample of thumbnails.
/// Verifies PhotoKit read access end to end before any real scanner/index is built.
/// See docs/sprint/SPRINT-002-PHOTOKIT-DIAGNOSTICS.md.
struct PhotoLibraryScanSampleView: View {
    private let assetProvider: PhotoAssetProvider
    private let sampleLimit = 150
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 4)]

    @State private var summary: LibraryScanSummary?
    @State private var items: [PhotoAssetSummaryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var networkAccessAllowed = false

    init(assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()) {
        self.assetProvider = assetProvider
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let summary {
                    summaryCard(summary)
                }

                Toggle("Allow iCloud network access", isOn: $networkAccessAllowed)
                    .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(items) { item in
                        ThumbnailCell(
                            item: item,
                            assetProvider: assetProvider,
                            networkAccessAllowed: networkAccessAllowed
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Scan Sample")
        .overlay {
            if isLoading {
                ProgressView("Scanning…")
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let summaryResult = assetProvider.scanSummary()
            async let sampleResult = assetProvider.fetchSampleAssets(limit: sampleLimit)
            let (s, sample) = try await (summaryResult, sampleResult)
            summary = s
            items = sample
        } catch {
            errorMessage = "Scan failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func summaryCard(_ summary: LibraryScanSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total \(summary.totalCount) · Photo \(summary.photoCount) · Video \(summary.videoCount)")
            Text("With date \(summary.withDateCount) · With GPS \(summary.withGPSCount)")
            if let oldest = summary.oldestCreationDate, let newest = summary.newestCreationDate {
                Text("\(oldest.formatted(date: .abbreviated, time: .omitted)) – \(newest.formatted(date: .abbreviated, time: .omitted))")
            }
            Text("Scan duration \(summary.scanDuration.formatted(.number.precision(.fractionLength(2))))s")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThumbnailCell: View {
    let item: PhotoAssetSummaryItem
    let assetProvider: PhotoAssetProvider
    let networkAccessAllowed: Bool

    @State private var image: PlatformImage?
    @State private var isICloudDownloadRequired = false

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isICloudDownloadRequired {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
            if item.mediaType == .video {
                Image(systemName: "video.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        // Distinct id per (asset, toggle) so flipping the network switch re-requests,
        // and leaving the grid cancels the in-flight PhotoKit request via withTaskCancellationHandler.
        .task(id: "\(item.id)-\(networkAccessAllowed)") {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        do {
            image = try await assetProvider.requestThumbnail(
                assetID: item.id,
                targetSize: CGSize(width: 180, height: 180),
                networkAccessAllowed: networkAccessAllowed,
                deliveryMode: .highQuality,
                contentMode: .fill
            )
            isICloudDownloadRequired = false
        } catch PhotoAssetProviderError.iCloudDownloadRequired {
            image = nil
            isICloudDownloadRequired = true
        } catch is CancellationError {
            // Cell left the screen before the request finished — nothing to do.
        } catch {
            NiziLogger.discovery.error("thumbnail_request_failed assetID=\(item.id, privacy: .private)")
        }
    }
}

#Preview {
    NavigationStack {
        PhotoLibraryScanSampleView()
    }
}
