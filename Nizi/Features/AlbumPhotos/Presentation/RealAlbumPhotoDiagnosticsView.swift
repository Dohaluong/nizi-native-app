//
//  RealAlbumPhotoDiagnosticsView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI
import Photos

/// Debug-only — exercises `ApplePhotosAlbumPhotoProvider` against real recent photos and shows
/// exactly what happened for each request: found/missing, degraded vs. final, duration, and a
/// cache-hit heuristic (no `.loading`/`.degraded` state before `.success` implies the cache
/// already had it). Never shown in production UI. See docs/specs/SPEC-REAL-ALBUM.md § 34.
struct RealAlbumPhotoDiagnosticsView: View {
    private struct LogRow: Identifiable {
        let id = UUID()
        let sourceIdentifier: String
        let requestedSize: CGSize
        let sawDegraded: Bool
        let finalState: String
        let likelyCacheHit: Bool
        let durationMs: Int
    }

    @State private var rows: [LogRow] = []
    @State private var isRunning = false
    @State private var statusMessage: String?

    private let provider = ApplePhotosAlbumPhotoProvider()

    var body: some View {
        List {
            Section {
                Button {
                    Task { await runDiagnostics() }
                } label: {
                    if isRunning { ProgressView() } else { Text("Load 10 Recent Photos (twice, to show cache hits)") }
                }
                .disabled(isRunning)
            } footer: {
                Text("Each photo is requested once (cold) and once more (should hit cache). Never shown in production.")
            }

            if let statusMessage {
                Section { Text(statusMessage).font(.subheadline).foregroundStyle(.secondary) }
            }

            ForEach(rows) { row in
                Section {
                    LabeledContent("Source ID", value: String(row.sourceIdentifier.prefix(24)))
                    LabeledContent("Requested size", value: "\(Int(row.requestedSize.width))×\(Int(row.requestedSize.height))")
                    LabeledContent("Degraded seen", value: row.sawDegraded ? "Yes" : "No")
                    LabeledContent("Final state", value: row.finalState)
                    LabeledContent("Likely cache hit", value: row.likelyCacheHit ? "Yes" : "No")
                    LabeledContent("Duration", value: "\(row.durationMs) ms")
                }
            }
        }
        .navigationTitle("Real Album Photo Diagnostics")
    }

    private func runDiagnostics() async {
        isRunning = true
        statusMessage = nil
        defer { isRunning = false }

        let status = await PhotoKitAuthorizationService().currentStatus()
        guard status == .full || status == .limited else {
            statusMessage = "Photos access not granted."
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var assetIDs: [String] = []
        fetchResult.enumerateObjects { asset, _, stop in
            assetIDs.append(asset.localIdentifier)
            if assetIDs.count >= 10 { stop.pointee = true }
        }
        guard !assetIDs.isEmpty else {
            statusMessage = "No recent photos found."
            return
        }

        var newRows: [LogRow] = []
        let targetSize = CGSize(width: 300, height: 300)

        // First pass — cold. Second pass — should hit the in-memory cache.
        for pass in 0..<2 {
            for assetID in assetIDs {
                let reference = AlbumPhotoReference(id: assetID, source: .applePhotos, sourceIdentifier: assetID, originalFilename: nil)
                let request = AlbumPhotoRequest(reference: reference, targetPixelSize: targetSize, contentMode: .fill, deliveryMode: .opportunistic)

                let start = Date()
                var sawDegraded = false
                var sawLoadingOrDegradedBeforeSuccess = false
                var finalState = "none"

                for await state in provider.loadImage(request: request) {
                    switch state {
                    case .loading:
                        sawLoadingOrDegradedBeforeSuccess = true
                    case .degraded:
                        sawDegraded = true
                        sawLoadingOrDegradedBeforeSuccess = true
                    case .success:
                        finalState = "success"
                    case .missing:
                        finalState = "missing"
                    case let .failure(error):
                        finalState = "failure(\(error))"
                    case .idle:
                        break
                    }
                }

                let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                if pass == 1 {
                    newRows.append(
                        LogRow(
                            sourceIdentifier: assetID, requestedSize: targetSize, sawDegraded: sawDegraded,
                            finalState: finalState, likelyCacheHit: !sawLoadingOrDegradedBeforeSuccess, durationMs: durationMs
                        )
                    )
                }
            }
        }

        rows = newRows
        statusMessage = "\(assetIDs.count) photo(s) requested twice each; showing the second (should-be-cached) pass."
    }
}
