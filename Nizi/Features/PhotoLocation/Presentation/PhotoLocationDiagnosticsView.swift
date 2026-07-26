//
//  PhotoLocationDiagnosticsView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI
import Photos

/// Debug-only screen for inspecting the location clustering/reverse-geocoding pipeline against
/// real recent photos — never a map, never raw EXIF (docs/specs/SPEC-ALBUM-PLANNER.md § 14).
/// Reruns clustering/cache/resolve itself (rather than calling `PhotoLocationEnriching`
/// end-to-end) specifically so it can show *which* step resolved each photo's place — a black-box
/// enrichment result can't distinguish "cache hit" from "freshly geocoded" from "failed."
struct PhotoLocationDiagnosticsView: View {
    private struct Row: Identifiable {
        let id: String
        let coordinate: PhotoCoordinate?
        let clusterId: String?
        let displayName: String?
        let source: String
        let errorDescription: String?
    }

    @State private var rows: [Row] = []
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    Task { await runDiagnostics() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Run Location Diagnostics")
                    }
                }
                .disabled(isLoading)
            } footer: {
                Text("Scans up to 20 recent photos that have GPS location, clusters them, and reverse-geocodes each cluster once.")
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(rows) { row in
                Section {
                    LabeledContent("Photo ID", value: String(row.id.prefix(24)))
                    if let coordinate = row.coordinate {
                        LabeledContent("Coordinate", value: "\(coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(4))))")
                    } else {
                        LabeledContent("Coordinate", value: "none")
                    }
                    if let clusterId = row.clusterId {
                        LabeledContent("Cluster", value: clusterId)
                    }
                    LabeledContent("Source", value: row.source)
                    if let displayName = row.displayName, !displayName.isEmpty {
                        LabeledContent("Place", value: displayName)
                    }
                    if let errorDescription = row.errorDescription {
                        Text(errorDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Photo Location Diagnostics")
    }

    private func runDiagnostics() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        let status = await PhotoKitAuthorizationService().currentStatus()
        guard status == .full || status == .limited else {
            statusMessage = "Photos access not granted."
            rows = []
            return
        }

        let assetIDs = Self.recentAssetIDsWithLocation(limit: 20)
        guard !assetIDs.isEmpty else {
            statusMessage = "No recent photos with GPS location found."
            rows = []
            return
        }

        let photos = PHAssetPlanningPhotoAdapter.planningPhotos(assetIDs: assetIDs, eventId: "diagnostics")
        let clusters = DefaultPhotoLocationClusterer().clusters(from: photos, maximumDistance: DefaultPhotoLocationClusterer.defaultMaximumDistance)
        let cache = InMemoryPhotoPlaceCache()
        let resolver = ApplePhotoPlaceResolver()

        var resultByPhotoId: [String: (displayName: String?, source: String, error: String?)] = [:]
        for cluster in clusters {
            let cacheKey = PhotoPlaceCacheKey(coordinate: cluster.representativeCoordinate)
            if let cached = await cache.place(for: cacheKey) {
                for photoId in cluster.photoIds { resultByPhotoId[photoId] = (cached.displayName, "cache hit", nil) }
                continue
            }
            do {
                let place = try await resolver.resolvePlace(for: cluster.representativeCoordinate)
                await cache.store(place, for: cacheKey)
                for photoId in cluster.photoIds { resultByPhotoId[photoId] = (place.displayName, "geocoded", nil) }
            } catch {
                for photoId in cluster.photoIds { resultByPhotoId[photoId] = (nil, "failed", String(describing: error)) }
            }
        }

        rows = photos.map { photo in
            let clusterId = clusters.first { $0.photoIds.contains(photo.id) }?.id
            let resolved = resultByPhotoId[photo.id]
            return Row(
                id: photo.id,
                coordinate: photo.coordinate,
                clusterId: clusterId,
                displayName: resolved?.displayName,
                source: photo.coordinate == nil ? "no coordinate" : (resolved?.source ?? "unresolved"),
                errorDescription: resolved?.error
            )
        }
        statusMessage = "\(photos.count) photo(s), \(clusters.count) cluster(s)."
    }

    private static func recentAssetIDsWithLocation(limit: Int) -> [String] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)

        var assetIDs: [String] = []
        fetchResult.enumerateObjects { asset, _, stop in
            if asset.location != nil {
                assetIDs.append(asset.localIdentifier)
            }
            if assetIDs.count >= limit {
                stop.pointee = true
            }
        }
        return assetIDs
    }
}
