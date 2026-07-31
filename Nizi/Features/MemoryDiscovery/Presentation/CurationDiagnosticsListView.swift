//
//  CurationDiagnosticsListView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI
import SwiftData

/// Debug-only Event picker for Curation Diagnostics — see
/// docs/sprint/SPRINT-SMART-EVENT-HIGHLIGHTS.md § 12-13. Not production navigation; reached only
/// via `PhotoLibraryDiagnosticsView`, itself only reachable through `HomeView`'s `#if DEBUG`
/// toolbar link. Same shape as `EventDiscoveryDebugListView` (plain List/ForEach, no fixtures).
struct CurationDiagnosticsListView: View {
    @Environment(\.modelContext) private var modelContext

    private struct Row: Identifiable {
        let event: PhotoEvent
        let selectedCount: Int?
        var id: UUID { event.id }
    }

    @State private var rows: [Row] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if rows.isEmpty, errorMessage == nil {
                Text("Chưa có event nào.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { row in
                NavigationLink {
                    CurationDiagnosticsDetailView(event: row.event)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.event.titleSuggestion)
                            .font(.headline)
                        Text(summary(for: row))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let location = row.event.primaryLocationLabel {
                            Text(location)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Curation Diagnostics")
        .task { await loadEvents() }
    }

    private func summary(for row: Row) -> String {
        let dateText = row.event.startDate.formatted(date: .abbreviated, time: .omitted)
        let selectedText = row.selectedCount.map { "\($0) selected" } ?? "not curated yet"
        return "\(dateText) · \(row.event.assetCount) photos · \(selectedText)"
    }

    private func loadEvents() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            let events = try await store.fetchEvents(sortedBy: .newestFirst)
            var loadedRows: [Row] = []
            loadedRows.reserveCapacity(events.count)
            for event in events {
                let result = try? await store.result(for: event.id)
                loadedRows.append(Row(event: event, selectedCount: result?.selectedAssetCount))
            }
            rows = loadedRows
        } catch {
            errorMessage = "Load failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        CurationDiagnosticsListView()
    }
    .modelContainer(
        for: [
            MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self
        ],
        inMemory: true
    )
}
