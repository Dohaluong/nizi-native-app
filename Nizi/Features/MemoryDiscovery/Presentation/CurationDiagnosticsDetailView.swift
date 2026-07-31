//
//  CurationDiagnosticsDetailView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI
import SwiftData

/// Debug-only per-Event curation inspector — see docs/sprint/SPRINT-SMART-EVENT-HIGHLIGHTS.md
/// § 14-17, § 21, § 57. Must be able to answer: why was this photo selected/rejected, which
/// duplicate cluster it's in, who won that cluster, whether Favorite was honored, and its score.
///
/// Re-runs `VisionEventPhotoAnalyzer` live (in-memory only) to get per-photo
/// sharpness/exposure/faceScore for display, joined by assetID with the already-persisted
/// `EventCurationResult` — deliberately not persisted itself (§ 43 explicitly defers a Vision
/// analysis cache to a future sprint). Cost is one extra Vision pass, paid only when a developer
/// opens this DEBUG-only screen.
struct CurationDiagnosticsDetailView: View {
    let event: PhotoEvent

    @Environment(\.modelContext) private var modelContext
    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var result: EventCurationResult?
    @State private var analyzedByAssetID: [String: AnalyzedPhoto] = [:]
    @State private var metrics: CurationDiagnosticsMetrics?
    @State private var isLoading = true
    @State private var isRecurating = false
    @State private var errorMessage: String?
    @State private var config = EventPhotoCurationEngine.Configuration.default

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            if let metrics {
                metricsSection(metrics)
            }

            tuningSection

            if let result {
                ForEach(clusters(in: result), id: \.clusterID) { cluster in
                    Section("Cluster \(cluster.clusterID.prefix(8))") {
                        ForEach(cluster.items) { item in
                            itemRow(item)
                        }
                    }
                }
            } else if isLoading {
                ProgressView().padding(.top, 40)
            }
        }
        .navigationTitle(event.titleSuggestion)
        .task { await load() }
    }

    // MARK: - Metrics

    private func metricsSection(_ metrics: CurationDiagnosticsMetrics) -> some View {
        Section("Metrics (§ 60)") {
            LabeledContent("Source photos", value: "\(metrics.sourcePhotoCount)")
            LabeledContent("Usable photos", value: "\(metrics.usablePhotoCount)")
            LabeledContent("Local clusters", value: "\(metrics.localClusterCount)")
            LabeledContent("Local selected", value: "\(metrics.localSelectedCount)")
            LabeledContent("Global duplicate suppressed", value: "\(metrics.globalDuplicateSuppressedCount)")
            LabeledContent("Final selected", value: "\(metrics.finalSelectedCount)")
            LabeledContent("Favorite (source)", value: "\(metrics.favoriteSourceCount)")
            LabeledContent("Favorite (selected)", value: "\(metrics.favoriteSelectedCount)")
            LabeledContent("User overrides", value: "\(metrics.userOverrideCount)")
        }
    }

    // MARK: - Tuning (§ 21 — thresholds must be tunable from Diagnostics)

    private var tuningSection: some View {
        Section("Tuning") {
            sliderRow("Min sharpness", value: $config.minimumUsableSharpness, range: 0...0.5)
            sliderRow("Min exposure", value: $config.minimumUsableExposure, range: 0...0.5)
            sliderRow("Global similarity threshold", value: Binding(
                get: { Double(config.globalSimilarityThreshold) },
                set: { config.globalSimilarityThreshold = Float($0) }
            ), range: 0...0.6)
            sliderRow("Favorite margin", value: $config.favoriteSignificantlyWorseMargin, range: 0...0.5)

            Button {
                Task { await recurate() }
            } label: {
                if isRecurating {
                    ProgressView()
                } else {
                    Text("Re-run with these settings")
                }
            }
            .disabled(isRecurating)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(value.wrappedValue, format: .number.precision(.fractionLength(2)))")
                .font(.caption)
            Slider(value: value, in: range)
        }
    }

    // MARK: - Cluster inspection (§ 17)

    private struct ClusterSection {
        let clusterID: String
        let items: [PhotoCurationItem]
    }

    private func clusters(in result: EventCurationResult) -> [ClusterSection] {
        let allItems = result.groups
            .sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { $0.items.sorted { $0.sortOrder < $1.sortOrder } }
        let grouped = Dictionary(grouping: allItems, by: \.similarityClusterID)
        return grouped.keys.sorted().map { key in
            ClusterSection(clusterID: key, items: grouped[key] ?? [])
        }
    }

    @ViewBuilder
    private func itemRow(_ item: PhotoCurationItem) -> some View {
        let analyzed = analyzedByAssetID[item.assetID]
        HStack(alignment: .top, spacing: 10) {
            ThumbnailView(assetID: item.assetID, assetProvider: assetProvider)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stateLabel(item))
                        .font(.caption2.bold())
                        .foregroundStyle(stateColor(item))
                    if analyzed?.metrics.isFavorite == true {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                Text("score \(item.qualityScore)")
                    .font(.caption2)
                if let analyzed {
                    Text("sharp \(analyzed.metrics.sharpness.formatted(.number.precision(.fractionLength(2)))) · exp \(analyzed.metrics.exposure.formatted(.number.precision(.fractionLength(2)))) · face \(analyzed.metrics.faceScore.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(analyzed.creationDate.formatted(date: .abbreviated, time: .standard))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let reason = reasonLabel(item) {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func stateLabel(_ item: PhotoCurationItem) -> String {
        switch item.selectionSource {
        case .userAdded: return "USER ADDED"
        case .userRemoved: return "USER REMOVED"
        case .systemSuggested: return item.isSelected ? "SELECTED" : "REJECTED"
        }
    }

    private func stateColor(_ item: PhotoCurationItem) -> Color {
        switch item.selectionSource {
        case .userAdded: return .blue
        case .userRemoved: return .red
        case .systemSuggested: return item.isSelected ? .green : .secondary
        }
    }

    private func reasonLabel(_ item: PhotoCurationItem) -> String? {
        if item.isSelected { return nil }
        if item.selectionSource == .userRemoved { return "User Removed" }
        switch item.rejectionReason {
        case .screenshot: return "Screenshot"
        case .document: return "Document"
        case .lowQuality: return "Low Quality"
        case .nearDuplicate: return "Near Duplicate"
        case .globalDuplicate: return "Global Duplicate"
        case .trimmed: return "Trimmed"
        case nil: return nil
        }
    }

    // MARK: - Loading

    private func makeStore() -> SwiftDataMemoryDiscoveryStore {
        SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
    }

    private func load() async {
        do {
            let store = makeStore()
            result = try await store.result(for: event.id)

            let assets = try await store.fetchAssets(ids: event.assetIDs)
            let sessions = try await store.fetchSessions(ids: event.sessionIDs)
            let analyzed = await VisionEventPhotoAnalyzer(assetProvider: assetProvider)
                .analyze(assets: assets, sessions: sessions) { _, _ in }
            analyzedByAssetID = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.assetID, $0) })

            if let result {
                metrics = CurationDiagnosticsMetrics.compute(
                    result: result,
                    isFavoriteByAssetID: analyzedByAssetID.mapValues(\.metrics.isFavorite)
                )
            }
        } catch {
            errorMessage = "Load failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func recurate() async {
        isRecurating = true
        defer { isRecurating = false }
        do {
            let store = makeStore()
            let service = EventPhotoCurationService(
                assetRepository: store,
                sessionRepository: store,
                curationRepository: store,
                analyzer: VisionEventPhotoAnalyzer(assetProvider: assetProvider),
                config: config
            )
            result = try await service.curate(event: event, forceRecurate: true) { _, _ in }
            await load()
        } catch {
            errorMessage = "Recurate failed: \(error.localizedDescription)"
        }
    }
}

private struct ThumbnailView: View {
    let assetID: String
    let assetProvider: PhotoAssetProvider
    @State private var image: PlatformImage?
    private static let targetSize = CGSize(width: 60, height: 60)

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: assetID) {
            image = assetProvider.cachedThumbnail(assetID: assetID, targetSize: Self.targetSize, contentMode: .fill)
            image = try? await assetProvider.requestThumbnail(
                assetID: assetID, targetSize: Self.targetSize,
                networkAccessAllowed: false, deliveryMode: .fast, contentMode: .fill
            )
        }
    }
}
