//
//  AlbumsListView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import SwiftUI
import SwiftData

/// The dedicated Album page — every Album the user has, year-filterable, each opening into
/// `AlbumDetailView`. Used to live inline on `HomeView` itself; moved out to its own screen so
/// Home only shows a short preview row (`HomeView.albumPreviewSection`) plus a "See all Albums"
/// entry point into this view. Pushed via `NavigationLink` from an already-open `NavigationStack`
/// (Home's own), so this view never wraps its own `NavigationStack`.
struct AlbumsListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var albums: [AlbumDraft] = []
    @State private var selectedYear: Int? = nil
    /// Drives the large-title collapse below — the vertical content offset of the `ScrollView`
    /// itself (`0` at rest, growing as the user scrolls up through the Albums).
    @State private var scrollOffset: CGFloat = 0
    /// Home/Events/Trips/Photobook/Diagnostics act like tabs — see `HomeView.selectTab`'s doc
    /// comment. Threaded down so this screen's own bottom bar jumps directly to another tab.
    var onSelectTab: (NiziBottomTabBar.Tab) -> Void = { _ in }

    /// `0` at rest (title fully large, on the trailing edge) to `1` once scrolled past
    /// `collapseDistance` (title fully shrunk into the toolbar, level with the back button).
    private var collapseProgress: CGFloat {
        min(max(scrollOffset / Self.collapseDistance, 0), 1)
    }
    private static let collapseDistance: CGFloat = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 0) {
                largeTitle

                if albums.isEmpty {
                    emptyState
                } else {
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
                            yearFilterHeader
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        // The system large title is never shown — `largeTitle` above (right-aligned, scrolls
        // with the content) and the `.topBarTrailing` toolbar item below (small, fixed in the
        // nav bar) together replace it, since `.navigationBarTitleDisplayMode(.large)` only ever
        // renders a *left*-aligned title with no alignment option of its own.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("album.list.title")
                    .font(.headline)
                    .opacity(collapseProgress)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            scrollOffset = newValue
        }
        .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
        .safeAreaInset(edge: .bottom) {
            NiziBottomTabBar(
                selected: .photobooks,
                onHome: { onSelectTab(.home) },
                onEvents: { onSelectTab(.events) },
                onTrips: { onSelectTab(.trips) },
                onPhotobooks: {},
                onDiagnostics: { onSelectTab(.diagnostics) }
            )
        }
        .task { await loadAlbums() }
    }

    /// Right-aligned, large-title-sized "Album" heading — fades and shrinks toward the trailing
    /// edge as `collapseProgress` climbs, crossfading into the small `.topBarTrailing` toolbar
    /// title above so there's always exactly one "Album" visible, never both or neither.
    private var largeTitle: some View {
        Text("album.list.title")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.bottom, 12)
            .scaleEffect(1 - collapseProgress * 0.4, anchor: .trailing)
            .opacity(1 - collapseProgress)
    }

    private var yearFilterHeader: some View {
        YearFilterBar(years: albumYears, selectedYear: $selectedYear)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))
    }

    private var albumYears: [Int] {
        Array(Set(albums.map(year(of:)))).sorted(by: >)
    }

    private var filteredAlbums: [AlbumDraft] {
        albums.filter { selectedYear == nil || year(of: $0) == selectedYear }
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("album.list.empty.title")
                .font(.headline)
            Text("album.list.empty.message")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func loadAlbums() async {
        do {
            let store = SwiftDataAlbumDraftStore(modelContainer: modelContext.container)
            albums = try await store.fetchAllDrafts()
        } catch {
            NiziLogger.discovery.error("albums_list_load_failed")
        }
    }

    private func saveUpdatedAlbum(_ draft: AlbumDraft) async {
        do {
            let store = SwiftDataAlbumDraftStore(modelContainer: modelContext.container)
            try await store.updateDraft(draft)
            await loadAlbums()
        } catch {
            NiziLogger.discovery.error("albums_list_update_failed")
        }
    }
}
