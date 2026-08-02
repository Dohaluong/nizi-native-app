//
//  TripsListView.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI
import SwiftData

/// Full Trips archive — data source is `PhotoTripRepository.fetchTrips()` only. Never re-runs
/// Trip Discovery, reverse geocoding, or Home Detection; this screen only reads what's already
/// persisted (SPRINT-NEXT-adjacent "Trips UI" task § 7).
struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var allTrips: [TripSummary] = []
    @State private var selectedClassification: TravelClassification? // nil = All
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Home/Events/Trips/Photobook/Diagnostics act like tabs — see `HomeView.selectTab`'s doc
    /// comment. Threaded down so this screen's own bottom bar jumps directly to another tab.
    var onSelectTab: (NiziBottomTabBar.Tab) -> Void = { _ in }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if allTrips.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        filterPicker
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(tripsByYear, id: \.year) { group in
                                Text(String(group.year))
                                    .font(.onboardingSerif(size: 32, weight: .bold))
                                    .foregroundStyle(TripsListStyle.primaryText)
                                    .padding(.top, 22)
                                    .padding(.bottom, 10)
                                ForEach(group.trips) { trip in
                                    NavigationLink {
                                        TripDetailView(trip: trip) { placeName in
                                            updateTripPlaceLocally(tripID: trip.id, placeName: placeName)
                                        }
                                    } label: {
                                        TripListRow(trip: trip)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
        }
        .background(TripsListStyle.background)
        .navigationTitle("trips.list.title")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(TripsListStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            NiziBottomTabBar(
                selected: .trips,
                onHome: { onSelectTab(.home) },
                onEvents: { onSelectTab(.events) },
                onTrips: {},
                onPhotobooks: { onSelectTab(.photobooks) },
                onDiagnostics: { onSelectTab(.diagnostics) }
            )
        }
        .task { await loadTrips() }
    }

    private var filterPicker: some View {
        Picker("trips.list.filter.label", selection: $selectedClassification) {
            Text("trips.list.filter.all").tag(TravelClassification?.none)
            Text(TravelClassification.domesticTrip.displayLabel).tag(TravelClassification?.some(.domesticTrip))
            Text(TravelClassification.internationalTrip.displayLabel).tag(TravelClassification?.some(.internationalTrip))
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // "All" intentionally includes every classification, including `.local`/`.dayTrip`/`.unknown`
    // — "Không cần Day Trip" means no dedicated filter chip for it, not that it's excluded from "All".
    private var filteredTrips: [TripSummary] {
        allTrips
            .filter { selectedClassification == nil || $0.classification == selectedClassification }
            .sorted { $0.startDate > $1.startDate } // defensive re-sort after filtering
    }

    /// § user request — group the list by year, newest year first, with a big year number as the
    /// section divider. `filteredTrips` is already newest-first, so each year's own trips only
    /// need grouping, not a second sort.
    private var tripsByYear: [(year: Int, trips: [TripSummary])] {
        let grouped = Dictionary(grouping: filteredTrips) { Calendar.current.component(.year, from: $0.startDate) }
        return grouped.keys.sorted(by: >).map { year in (year: year, trips: grouped[year] ?? []) }
    }

    private func loadTrips() async {
        isLoading = true
        errorMessage = nil
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            let trips = try await store.fetchTrips()
            allTrips = try await TripSummaryBuilder.makeSummaries(trips: trips, eventRepository: store)
        } catch {
            errorMessage = localizedString("trips.list.error.load_failed", defaultValue: "Couldn't load your trips.")
        }
        isLoading = false
    }

    private func updateTripPlaceLocally(tripID: UUID, placeName: String) {
        guard let index = allTrips.firstIndex(where: { $0.id == tripID }) else { return }
        allTrips[index].primaryPlaceName = placeName
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("trips.list.empty.title")
                .font(.headline)
                .foregroundStyle(TripsListStyle.primaryText)
            Text("trips.list.empty.message")
                .font(.subheadline)
                .foregroundStyle(TripsListStyle.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(TripsListStyle.mutedText)
                .multilineTextAlignment(.center)
            Button("common.action.retry") { Task { await loadTrips() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private enum TripsListStyle {
    static let background = Color(red: 14 / 255, green: 13 / 255, blue: 16 / 255)
    static let primaryText = Color(red: 246 / 255, green: 241 / 255, blue: 234 / 255)
    static let mutedText = primaryText.opacity(0.45)
}

/// One row per Trip — a fixed 60×60 cover thumbnail + place/metadata text, resolving from an
/// already-built `TripSummary` instead of a `PhotoEvent`.
private struct TripListRow: View {
    let trip: TripSummary
    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var coverImage: PlatformImage?
    private static let thumbnailSize = CGSize(width: 120, height: 120)

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.09))
                if let coverImage {
                    Image(uiImage: coverImage).resizable().scaledToFill()
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(placeText)
                    .font(.system(size: 14.5))
                    .foregroundStyle(TripsListStyle.primaryText)
                    .lineLimit(1)
                Text(metadataText)
                    .font(.system(size: 12))
                    .foregroundStyle(TripsListStyle.mutedText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .task(id: trip.coverAssetID) { await loadCover() }
    }

    private var placeText: String { trip.displayPlaceName ?? trip.classification.displayLabel }

    private var metadataText: String {
        let events = localizedString("trip.count.events", defaultValue: "\(trip.eventCount) events")
        let photos = localizedString("trip.count.photos", defaultValue: "\(trip.photoCount) photos")
        return "\(trip.dateRangeText) · \(events) · \(photos)"
    }

    private func loadCover() async {
        guard let coverAssetID = trip.coverAssetID else { return }
        coverImage = assetProvider.cachedThumbnail(assetID: coverAssetID, targetSize: Self.thumbnailSize, contentMode: .fill)
        guard coverImage == nil else { return }
        do {
            coverImage = try await assetProvider.requestThumbnail(
                assetID: coverAssetID, targetSize: Self.thumbnailSize,
                networkAccessAllowed: false, deliveryMode: .fast, contentMode: .fill
            )
        } catch {
            NiziLogger.discovery.notice("trip_list_row_cover_unavailable")
        }
    }
}

#Preview {
    NavigationStack {
        TripsListView()
    }
    .modelContainer(
        for: [
            MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
        ],
        inMemory: true
    )
}
