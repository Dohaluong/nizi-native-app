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
                        albumPreviewSection
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
            for: [MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self],
            inMemory: true
        )
}
