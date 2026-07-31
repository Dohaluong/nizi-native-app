//
//  HomeDetectionDiagnosticsView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI
import SwiftData

/// Debug-only screen: run `LocationIntelligenceEngine` against the current Local Memory Index and
/// show every candidate cluster ranked by Home score, per SPRINT-SMART-EVENT-TRAVEL-DISCOVERY § 39.
struct HomeDetectionDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    private struct CandidateRow: Identifiable {
        let id: UUID
        let cluster: LocationCluster
        let score: Double
        let confidence: HomeConfidence?
        let isWinner: Bool
        let isFamiliar: Bool
    }

    @State private var rows: [CandidateRow] = []
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if rows.isEmpty {
                Text("Chưa có cluster nào. Bấm Run để phân tích Local Memory Index hiện tại.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.isWinner ? "🏠 HOME" : (row.isFamiliar ? "Familiar" : "Candidate"))
                            .font(.headline)
                            .foregroundStyle(row.isWinner ? Color.accentColor : .primary)
                        Spacer()
                        Text(row.score.formatted(.number.precision(.fractionLength(2))))
                            .font(.headline.monospacedDigit())
                    }
                    Text("\(row.cluster.distinctDayCount) distinct days · \(row.cluster.distinctMonthCount) months · \(row.cluster.visitRunCount) visits · \(row.cluster.assetCount) photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("First seen \(row.cluster.firstSeenAt.formatted(date: .abbreviated, time: .omitted)) · Last seen \(row.cluster.lastSeenAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Evening/night \(Int(row.cluster.eveningOrNightAssetRatio * 100))% · Confidence \(row.confidence?.rawValue ?? "unknown")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Home Detection")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await run() }
                } label: {
                    if isRunning {
                        ProgressView()
                    } else {
                        Text("Run")
                    }
                }
                .disabled(isRunning)
            }
        }
        .task { await run() }
    }

    private func run() async {
        isRunning = true
        errorMessage = nil
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            let assets = try await store.fetchClusterableAssets()
            let config = EventDiscoveryConfig.default
            let result = LocationIntelligenceEngine.analyze(from: assets, config: config)
            let familiarClusterIDs = Set(result.familiarPlaces.map(\.clusterID))

            rows = result.clusters
                .map { cluster -> CandidateRow in
                    let score = LocationIntelligenceEngine.homeScore(for: cluster)
                    return CandidateRow(
                        id: cluster.id, cluster: cluster, score: score,
                        confidence: LocationIntelligenceEngine.homeConfidence(for: score, config: config),
                        isWinner: cluster.id == result.home?.clusterID,
                        isFamiliar: familiarClusterIDs.contains(cluster.id)
                    )
                }
                .sorted { $0.score > $1.score }
        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
        }
        isRunning = false
    }
}

#Preview {
    NavigationStack {
        HomeDetectionDiagnosticsView()
    }
    .modelContainer(
        for: [
            MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
        ],
        inMemory: true
    )
}
