//
//  EventBoundaryDiagnosticsView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI
import SwiftData

/// Debug-only screen: runs Event Discovery, then independently re-evaluates every consecutive
/// session pair through `DefaultEventBoundaryEvaluator` to show exactly why it MERGEd or SPLIT
/// them — the SPRINT-SMART-EVENT-TRAVEL-DISCOVERY § 38 trace table, per-pair. Tracks the same
/// running group-duration state `EventDiscoveryEngine.groupSessionsForMerging` uses internally,
/// so the displayed effective threshold matches what the real engine actually saw.
struct EventBoundaryDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    private struct PairTrace: Identifiable {
        let id = UUID()
        let previous: PhotoSession
        let next: PhotoSession
        let decision: EventBoundaryDecision
    }

    @State private var traces: [PairTrace] = []
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            DiagnosticsBanner(title: "Preview only", subtitle: "Does not modify persisted Events", tone: .previewOnly)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if traces.isEmpty {
                Text("Chưa có dữ liệu. Bấm Run để chạy Event Discovery và xem trace từng cặp session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(traces) { trace in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(trace.previous.startDate.formatted(date: .abbreviated, time: .shortened))
                        Image(systemName: "arrow.right")
                        Text(trace.next.startDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption.bold())

                    ForEach(trace.decision.reasons) { reason in
                        HStack {
                            Text(reason.name)
                            Spacer()
                            Text(reason.detail)
                                .foregroundStyle(.secondary)
                            Text(signedString(reason.contribution))
                                .foregroundStyle(reason.contribution >= 0 ? .green : .red)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .font(.caption2)
                    }

                    HStack {
                        Text("TOTAL")
                        Spacer()
                        Text(signedString(trace.decision.score))
                    }
                    .font(.caption.bold())

                    if trace.decision.isHardBoundary {
                        Text("HARD BOUNDARY: YES")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                    }

                    Text(trace.decision.action == .merge ? "DECISION: MERGE" : "DECISION: SPLIT")
                        .font(.caption.bold())
                        .foregroundStyle(trace.decision.action == .merge ? .green : .red)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Event Boundary")
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
            let result = EventDiscoveryEngine.discover(from: assets, config: config)
            let evaluator = DefaultEventBoundaryEvaluator(config: config)
            let sorted = result.sessions.sorted { $0.startDate < $1.startDate }

            var newTraces: [PairTrace] = []
            guard sorted.count > 1 else {
                traces = []
                isRunning = false
                return
            }

            var groupStart = sorted[0].startDate
            var sessionCountInGroup = 1
            for index in 1..<sorted.count {
                let previous = sorted[index - 1]
                let next = sorted[index]
                let context = EventBoundaryContext(
                    home: result.home, familiarPlaces: result.familiarPlaces,
                    currentEventDurationHours: previous.endDate.timeIntervalSince(groupStart) / 3600,
                    currentEventSessionCount: sessionCountInGroup
                )
                let decision = evaluator.evaluate(previous: previous, next: next, context: context)
                newTraces.append(PairTrace(previous: previous, next: next, decision: decision))

                if decision.action == .merge {
                    sessionCountInGroup += 1
                } else {
                    groupStart = next.startDate
                    sessionCountInGroup = 1
                }
            }
            traces = newTraces
        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
        }
        isRunning = false
    }
}

#Preview {
    NavigationStack {
        EventBoundaryDiagnosticsView()
    }
    .modelContainer(
        for: [
            MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
        ],
        inMemory: true
    )
}
