//
//  EventDiscoveryDebugListView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// Debug-only screen: run event discovery against the current Local Memory Index and inspect
/// what events it produces, with score and reasons. See docs/sprint/SPRINT-004-EVENT-DISCOVERY.md
/// task 11 ("Candidate list debug") — this is not the real Event Review UI (a later sprint).
struct EventDiscoveryDebugListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var events: [PhotoEvent] = []
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if events.isEmpty {
                Text("Chưa có event nào. Chạy Local Memory Index scan trước, rồi bấm Run.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.titleSuggestion)
                        .font(.headline)
                    Text("\(event.eventType.rawValue) · \(event.assetCount) ảnh · \(event.sessionCount) phiên · score \(event.score.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(event.discoveryReasons) { reason in
                        Text("• \(reason.text)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Event Discovery Debug")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await runDiscovery() }
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
        .task { await loadEvents() }
    }

    private func makeStore() -> SwiftDataMemoryDiscoveryStore {
        SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
    }

    private func loadEvents() async {
        do {
            events = try await makeStore().fetchEvents(sortedBy: .scoreDescending)
        } catch {
            errorMessage = "Load failed: \(error.localizedDescription)"
        }
    }

    private func runDiscovery() async {
        isRunning = true
        errorMessage = nil
        do {
            let store = makeStore()
            let useCase = DiscoverEventsUseCase(
                assetRepository: store,
                sessionRepository: store,
                eventRepository: store
            )
            events = try await useCase.execute()
        } catch {
            errorMessage = "Discovery failed: \(error.localizedDescription)"
        }
        isRunning = false
    }
}

#Preview {
    NavigationStack {
        EventDiscoveryDebugListView()
    }
    .modelContainer(
        for: [MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self],
        inMemory: true
    )
}
