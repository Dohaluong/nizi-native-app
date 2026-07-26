//
//  HomeView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// The app's real Home — an album timeline, not Memory Discovery.
/// See docs/sprint/SPRINT-005-ADDENUM.md: Memory Discovery is a secondary workflow reached
/// through the Quick Action card, never the main screen.
///
/// There is no Album module yet (a separate, not-yet-built module — see
/// docs/architecture/ARCHITECTURE.md § 2), so the timeline itself is an honest empty state
/// for now rather than a port of the webapp design. See docs/sprint/SPRINT-005-INTEGRATION-CHECKLIST.md.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var indexedPhotoCount = 0
    @State private var newEventCount = 0
    @State private var albums: [AlbumDraft] = []
    @State private var selectedAlbumYear: Int? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    NavigationLink {
                        EventListView()
                    } label: {
                        quickActionCard
                    }
                    .buttonStyle(.plain)

                    if albums.isEmpty {
                        emptyTimeline
                    } else {
                        albumListSection
                    }
                }
                .padding()
            }
            .navigationTitle("Nizi")
            .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("Diagnostics") {
                        PhotoLibraryDiagnosticsView()
                    }
                    .font(.caption)
                }
                #endif
            }
            .task {
                await loadStats()
                await loadAlbums()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("home.greeting")
                .font(.title2.bold())
            Text(localizedString("home.stats.summary", defaultValue: "0 Album · \(indexedPhotoCount) photos surveyed"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var quickActionCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("event.list.title")
                    .font(.headline)
                if newEventCount > 0 {
                    Text(localizedString("home.quick_action.subtitle.new_count", defaultValue: "\(newEventCount) new suggestions"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("home.quick_action.subtitle.view_all")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // Matches the agreed-upon design in `AlbumCardDesignPreview.swift` (`AlbumDesignCard` +
    // `YearFilterBar`), now backed by real `AlbumDraft`s and real cover photos via `AlbumPhotoView`
    // instead of the mock `AlbumCardSample` data that design was originally previewed with. Every
    // Album matching the selected year is listed (not just one); the `YearFilterBar` pins to the
    // top of the scroll view while its Albums scroll underneath.
    private var albumListSection: some View {
        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(filteredAlbums) { album in
                    NavigationLink {
                        AlbumDetailView(draft: album) { updated in
                            await saveUpdatedAlbum(updated)
                        } onDelete: {
                            await loadAlbums()
                        }
                    } label: {
                        AlbumDesignCard(album: cardSample(for: album))
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                albumSectionHeader
            }
        }
    }

    private var albumSectionHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("album.list.title")
                .font(.headline)
            YearFilterBar(years: albumYears, selectedYear: $selectedAlbumYear)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var albumYears: [Int] {
        Array(Set(albums.map(year(of:)))).sorted(by: >)
    }

    private var filteredAlbums: [AlbumDraft] {
        albums.filter { selectedAlbumYear == nil || year(of: $0) == selectedAlbumYear }
    }

    private func cardSample(for draft: AlbumDraft) -> AlbumCardSample {
        AlbumCardSample(
            title: draft.title,
            subtitle: draft.subtitle ?? draft.primaryLocationName
                ?? localizedString("album.card.subtitle_fallback", defaultValue: "Your memories, beautifully collected."),
            photoCount: draft.totalPhotoCount,
            dateRange: dateRangeText(for: draft),
            imageName: "photo.on.rectangle.angled",
            year: year(of: draft),
            coverPhoto: draft.coverPhotoReference
        )
    }

    private func dateRangeText(for draft: AlbumDraft) -> String {
        guard let start = draft.startDate else {
            return draft.createdAt.formatted(date: .abbreviated, time: .omitted)
        }
        guard let end = draft.endDate, !Calendar.current.isDate(start, inSameDayAs: end) else {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return EventDateRangeFormatter.format(start: start, end: end)
    }

    private func year(of draft: AlbumDraft) -> Int {
        Calendar.current.component(.year, from: draft.startDate ?? draft.createdAt)
    }

    private var emptyTimeline: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("home.empty_timeline.title")
                .font(.headline)
            Text("home.empty_timeline.message")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func loadStats() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            indexedPhotoCount = try await store.totalIndexedCount()
            let events = try await store.fetchEvents(sortedBy: .scoreDescending)
            newEventCount = events.filter { $0.status == .new }.count
        } catch {
            NiziLogger.discovery.error("home_stats_load_failed")
        }
    }

    private func loadAlbums() async {
        do {
            let store = SwiftDataAlbumDraftStore(modelContainer: modelContext.container)
            albums = try await store.fetchAllDrafts()
        } catch {
            NiziLogger.discovery.error("home_albums_load_failed")
        }
    }

    private func saveUpdatedAlbum(_ draft: AlbumDraft) async {
        do {
            let store = SwiftDataAlbumDraftStore(modelContainer: modelContext.container)
            try await store.updateDraft(draft)
            await loadAlbums()
        } catch {
            NiziLogger.discovery.error("home_album_update_failed")
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(
            for: [MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self],
            inMemory: true
        )
}
