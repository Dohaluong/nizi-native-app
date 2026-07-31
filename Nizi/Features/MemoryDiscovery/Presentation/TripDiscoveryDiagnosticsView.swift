//
//  TripDiscoveryDiagnosticsView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI
import SwiftData

/// Debug-only screen: shows every persisted `PhotoTrip` — place/country, day span,
/// classification, confidence, event count, departure/return-home flags — per
/// SPRINT-SMART-EVENT-TRAVEL-DISCOVERY § 40. "Run" goes through the real
/// `DiscoverEventsUseCase` pipeline (same one production onboarding uses), so classification
/// (which needs reverse-geocoding) actually happens, not just grouping.
struct TripDiscoveryDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var trips: [PhotoTrip] = []
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if trips.isEmpty {
                Text("Chưa có trip nào. Bấm Run để chạy lại toàn bộ discovery pipeline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(trips) { trip in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(trip.primaryPlaceName ?? "Unknown place")
                            .font(.headline)
                        Spacer()
                        Text(trip.classification.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(color(for: trip.classification))
                    }
                    Text("\(dayCount(trip)) days · Confidence \(trip.confidence.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Events: \(trip.eventIDs.count) · Countries: \(trip.travelContext.countryCodes.sorted().joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text(trip.travelContext.hasDepartureFromHome ? "Departure from home: YES" : "Departure from home: NO")
                        Text(trip.travelContext.hasReturnToHome ? "Return home: YES" : "Return home: NO")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Detected Trips")
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
        .task { await load() }
    }

    private func color(for classification: TravelClassification) -> Color {
        switch classification {
        case .internationalTrip: .purple
        case .domesticTrip: .blue
        case .dayTrip: .green
        case .local: .secondary
        case .unknown: .gray
        }
    }

    private func dayCount(_ trip: PhotoTrip) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: trip.startDate), to: calendar.startOfDay(for: trip.endDate)
        ).day ?? 0
        return max(days, 0) + 1
    }

    private func load() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            trips = try await store.fetchTrips()
        } catch {
            errorMessage = "Load failed: \(error.localizedDescription)"
        }
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
            trips = try await store.fetchTrips()
        } catch {
            errorMessage = "Discovery failed: \(error.localizedDescription)"
        }
        isRunning = false
    }
}

#Preview {
    NavigationStack {
        TripDiscoveryDiagnosticsView()
    }
    .modelContainer(
        for: [
            MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
        ],
        inMemory: true
    )
}
