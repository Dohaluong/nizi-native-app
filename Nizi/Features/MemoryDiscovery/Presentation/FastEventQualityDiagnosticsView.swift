//
//  FastEventQualityDiagnosticsView.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI
import SwiftData

/// Debug-only screen: runs Event Discovery (which now folds in Fast Event Quality — see
/// `EventDiscoveryEngine.discover`), then re-derives each Event's `EventQualityTrace` standalone
/// via `FastEventQualityService.classify` for display — same "recompute for display, never
/// persist the trace" pattern `EventBoundaryDiagnosticsView` already uses for boundary decisions.
/// Per docs/sprint/SPRINT-FAST-EVENT-QUALITY.md § 16-17: must show score, visibility, and full
/// per-signal reasons, not just a bare number.
struct FastEventQualityDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var results: [FastEventQualityService.Result] = []
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            DiagnosticsBanner(
                title: "Production Event Quality", subtitle: "Same scoring Event Discovery uses in production", tone: .production
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if results.isEmpty {
                Text("Chưa có dữ liệu. Bấm Run để chạy Event Discovery và xem Fast Event Quality từng Event.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(results, id: \.event.id) { result in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(result.event.titleSuggestion)
                            .font(.caption.bold())
                        Spacer()
                        Text(result.trace.visibility.rawValue.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(color(for: result.trace.visibility))
                        Text(String(format: "%.2f", result.trace.score))
                            .font(.caption.bold())
                    }

                    ForEach(result.trace.reasons) { reason in
                        HStack {
                            Text(reason.name)
                            Spacer()
                            Text(reason.detail)
                                .foregroundStyle(.secondary)
                            Text(signedString(reason.contribution))
                                .foregroundStyle(reason.contribution > 0 ? .green : (reason.contribution < 0 ? .red : .secondary))
                                .frame(width: 56, alignment: .trailing)
                        }
                        .font(.caption2)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Fast Event Quality")
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

    private func color(for visibility: EventVisibility) -> Color {
        switch visibility {
        case .normal: .green
        case .lowValue: .orange
        case .hiddenNoise: .red
        }
    }

    private func signedString(_ value: Double) -> String {
        String(format: "%+.2f", value)
    }

    private func run() async {
        isRunning = true
        errorMessage = nil
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            let assets = try await store.fetchClusterableAssets()
            let config = EventDiscoveryConfig.default
            let discovery = EventDiscoveryEngine.discover(from: assets, config: config)

            let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            results = FastEventQualityService.classify(
                events: discovery.events, assetsByID: assetsByID, trips: discovery.trips,
                home: discovery.home, familiarPlaces: discovery.familiarPlaces, config: config
            )
        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
        }
        isRunning = false
    }
}

#Preview {
    NavigationStack {
        FastEventQualityDiagnosticsView()
    }
    .modelContainer(
        for: [
            MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
        ],
        inMemory: true
    )
}
