//
//  MemoryPotentialDiagnosticsView.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI
import SwiftData

/// Debug-only screen: "Run" executes the real `DiscoverEventsUseCase` (same production pipeline
/// — `isAutoMemory`/`autoMemoryScore` actually persist, same as Detected Trips already does), then
/// re-derives each Event's `MemoryPotentialTrace` standalone via `MemoryPotentialEvaluator` for
/// display — same "recompute for display, never persist the trace" pattern
/// `FastEventQualityDiagnosticsView` already uses. Per SPRINT-NEXT § 24: must show score, Auto
/// Memory YES/NO, and full per-signal reasons.
struct MemoryPotentialDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var results: [MemoryPotentialEvaluator.Result] = []
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            DiagnosticsBanner(
                title: "Production pipeline result",
                subtitle: "isAutoMemory persisted via Event Discovery; reasons recomputed for display",
                tone: .production
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if results.isEmpty {
                Text("Chưa có dữ liệu. Bấm Run để chạy Event Discovery và xem Memory Potential từng Event.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(results, id: \.event.id) { result in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(result.event.titleSuggestion)
                            .font(.caption.bold())
                        Spacer()
                        Text(result.trace.isAutoMemory ? "AUTO MEMORY: YES" : "AUTO MEMORY: NO")
                            .font(.caption2.bold())
                            .foregroundStyle(result.trace.isAutoMemory ? .green : .secondary)
                        Text(String(format: "%.2f", result.trace.score))
                            .font(.caption.bold())
                    }

                    ForEach(result.trace.reasons) { reason in
                        HStack {
                            Text(reason.name)
                            Spacer()
                            Text(reason.detail)
                                .foregroundStyle(.secondary)
                            Image(systemName: reason.isMet ? "checkmark" : "xmark")
                                .foregroundStyle(reason.isMet ? .green : .secondary)
                                .frame(width: 20, alignment: .trailing)
                        }
                        .font(.caption2)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Memory Potential")
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
            let useCase = DiscoverEventsUseCase(
                assetRepository: store,
                sessionRepository: store,
                eventRepository: store,
                locationIntelligenceRepository: store,
                tripRepository: store
            )
            _ = try await useCase.execute()

            let assets = try await store.fetchClusterableAssets()
            let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            let events = try await store.fetchEvents(sortedBy: .scoreDescending)
            let trips = try await store.fetchTrips()
            let home = try await store.fetchHome()
            let familiarPlaces = try await store.fetchFamiliarPlaces()

            results = MemoryPotentialEvaluator.evaluate(
                events: events, trips: trips, assetsByID: assetsByID,
                home: home, familiarPlaces: familiarPlaces, config: .default
            )
        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
        }
        isRunning = false
    }
}

#Preview {
    NavigationStack {
        MemoryPotentialDiagnosticsView()
    }
    .modelContainer(
        for: [
            MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
        ],
        inMemory: true
    )
}
