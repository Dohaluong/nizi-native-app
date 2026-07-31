//
//  HomeView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

private enum HomeRoute: Hashable {
    case events
}

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
    @State private var eventCount = 0
    @State private var albums: [AlbumDraft] = []
    @State private var latestMemory: MemoryCandidate?
    @State private var lovedEvents: [PhotoEvent] = []
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if let latestMemory {
                        memorySection(candidate: latestMemory)
                        // This placement was verified on device: the card immediately below
                        // Memory receives touches reliably, unlike the former header placement.
                        eventDiscoveryLink
                    }

                    lovedMemoriesSection

                    if albums.isEmpty {
                        emptyTimeline
                    } else {
                        albumPreviewSection
                    }
                }
                .padding()
            }
            .navigationTitle("Nizi")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .events:
                    EventListView()
                }
            }
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
                await loadMemory()
                await loadLovedEvents()
            }
            // Returning from Event List keeps Home alive in the navigation stack, so its initial
            // `.task` does not run again. Refresh the user-owned loved section on return.
            .onAppear {
                Task { await loadLovedEvents() }
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

    /// Memory follows the Event discovery card, then Album content.
    private func memorySection(candidate: MemoryCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("home.memory_section.title")
                .font(.headline)

            NavigationLink {
                MemoryViewerView(candidate: candidate, onContinue: {})
            } label: {
                MemoryHeroCard(candidate: candidate)
            }
            .buttonStyle(.plain)
        }
    }

    /// Direct entry into the Events list, displayed immediately below the Memory card.
    private var eventDiscoveryLink: some View {
        NavigationLink(value: HomeRoute.events) {
            eventDiscoveryCard
        }
        .buttonStyle(.plain)
    }

    private var eventDiscoveryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Nizi đã tìm thấy \(eventCount) sự kiện.")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Hãy xem và lưu lại những kỷ niệm đáng nhớ.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var lovedMemoriesSection: some View {
        if !lovedEvents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Kỷ niệm")
                    .font(.headline)

                ForEach(lovedEvents) { event in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink {
                            MemoryDetailView(event: event)
                        } label: {
                            EventCardView(
                                event: event,
                                assetProvider: PhotoKitAssetProvider(),
                                onCoverLoaded: { _ in }
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: EventCardView.cardHeight)
                        }

                        Button {
                            Task { await setLoved(event, isLoved: false) }
                        } label: {
                            Image(systemName: "heart.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.red)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.28), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Bỏ yêu thích sự kiện")
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Home only ever shows a short taste of the Albums (§ layout request: moved the full list out
    /// to its own `AlbumsListView` page) — the 6 most recent (`SwiftDataAlbumDraftStore.
    /// fetchAllDrafts()` already sorts newest-`createdAt`-first) in one horizontal-scrolling row of
    /// compact `AlbumMiniCard`s, a trailing "see all" tile as the row's last cell, and a second,
    /// full-width "see all" link below the row — both open the same `AlbumsListView`.
    private var albumPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("home.album_preview.title")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(homeAlbumPreview) { album in
                        NavigationLink {
                            AlbumDetailView(draft: album) { updated in
                                await saveUpdatedAlbum(updated)
                            } onDelete: {
                                await loadAlbums()
                            }
                        } label: {
                            AlbumMiniCard(album: cardSample(for: album))
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        AlbumsListView()
                    } label: {
                        AlbumSeeAllTile()
                    }
                    .buttonStyle(.plain)
                }
            }

            NavigationLink {
                AlbumsListView()
            } label: {
                HStack {
                    Text("home.album_preview.see_all")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Only ever the first 6 — a taste, not the whole list (that's what the "see all" entry
    /// points are for).
    private var homeAlbumPreview: [AlbumDraft] {
        Array(albums.prefix(6))
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
            eventCount = events.count
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

    private func loadMemory() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            latestMemory = try await store.fetchLatest()
        } catch {
            NiziLogger.discovery.error("home_memory_load_failed")
        }
    }

    private func loadLovedEvents() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            lovedEvents = try await store.fetchLovedEvents()
        } catch {
            NiziLogger.discovery.error("home_loved_events_load_failed")
        }
    }

    private func setLoved(_ event: PhotoEvent, isLoved: Bool) async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            try await store.setEventLoved(eventID: event.id, isLoved: isLoved)
            withAnimation(.easeInOut(duration: 0.2)) {
                lovedEvents.removeAll { $0.id == event.id }
            }
        } catch {
            NiziLogger.discovery.error("home_loved_event_update_failed")
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

/// One compact Album tile for `HomeView.albumPreviewSection`'s horizontal row — same real
/// cover-photo pipeline `AlbumDesignCard` uses, just a fraction of its size (§ layout request:
/// "kích thước nhỏ hơn Album hiện tại" — the full-size `AlbumDesignCard` now only appears on the
/// dedicated `AlbumsListView`).
private struct AlbumMiniCard: View {
    let album: AlbumCardSample
    private let size: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            coverImage
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(localizedString("album.photosCount", defaultValue: "\(album.photoCount) photos"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: size, alignment: .leading)
    }

    @ViewBuilder
    private var coverImage: some View {
        Group {
            if let coverPhoto = album.coverPhoto {
                AlbumPhotoView(
                    reference: coverPhoto, crop: .centered, contentMode: .fill,
                    targetSize: CGSize(width: size * 2, height: size * 2)
                )
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: album.imageName)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(size * 0.28)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// `HomeView.memorySection`'s hero tile — plain PhotoKit thumbnail loading (`PhotoAssetProvider`,
/// same idiom as `EventCardView`'s cover), not `AlbumPhotoView`, since `MemoryCandidate.
/// coverAssetID` is a raw asset identifier, not an `AlbumPhotoReference`.
private struct MemoryHeroCard: View {
    let candidate: MemoryCandidate

    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var coverImage: PlatformImage?
    private static let targetSize = CGSize(width: 640, height: 640)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.secondary.opacity(0.15))
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text("home.memory_section.badge")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.85))
                if let placeName = candidate.placeName {
                    Text(placeName)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Text(EventDateRangeFormatter.format(start: candidate.startDate, end: candidate.endDate))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task {
            coverImage = assetProvider.cachedThumbnail(
                assetID: candidate.coverAssetID, targetSize: Self.targetSize, contentMode: .fill
            )
            do {
                coverImage = try await assetProvider.requestThumbnail(
                    assetID: candidate.coverAssetID,
                    targetSize: Self.targetSize,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality,
                    contentMode: .fill
                )
            } catch {
                NiziLogger.discovery.error("home_memory_cover_load_failed error=\(String(describing: error), privacy: .public)")
            }
        }
    }
}

/// The trailing cell in `HomeView.albumPreviewSection`'s row — same tile footprint as
/// `AlbumMiniCard` (so it lines up in the same scrolling row) but with no cover photo of its own,
/// opening `AlbumsListView` instead of an `AlbumDetailView`.
private struct AlbumSeeAllTile: View {
    private let size: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color(.tertiarySystemFill)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("home.album_preview.see_all")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: size, alignment: .leading)
        }
        .frame(width: size, alignment: .leading)
    }
}

#Preview {
    HomeView()
        .modelContainer(
            for: [
                MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
                MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
                MDMemoryCandidate.self,
                MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
            ],
            inMemory: true
        )
}
