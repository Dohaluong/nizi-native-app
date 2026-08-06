//
//  HomeView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData
import UIKit

private enum HomeRoute: Hashable {
    case events
    case trips
    case photobooks
    case diagnostics
    case backgroundScan
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
    @Environment(BackgroundScanCoordinator.self) private var backgroundScanCoordinator
    @State private var indexedPhotoCount = 0
    @State private var eventCount = 0
    @State private var albums: [AlbumDraft] = []
    @State private var memoryEvents: [PhotoEvent] = []
    @State private var tripSummaries: [TripSummary] = []
    @State private var navigationPath = NavigationPath()
    @State private var isMoveImportPresented = false
    /// Album cover cache must survive Home's ordinary state updates. Constructing this provider
    /// inline in `body` created a fresh `AlbumImageCache` after every re-render, so the same
    /// Photobook card repeatedly re-requested its cover from PhotoKit.
    @State private var albumPhotoProvider = ApplePhotosAlbumPhotoProvider()
    /// The Home rail uses the same thumbnail cache as Memories. Unlike AlbumPhotoView's stream
    /// state machine, it never replaces an already-visible cover with a spinner when a lazy cell
    /// is reconstructed during scrolling.
    @State private var photobookThumbnailProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var homeThumbnailProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    /// Seeds the Loved Memories rail's random pick. Fixed once per app session (not reshuffled on
    /// every body re-evaluation, which would make the rail's contents flicker) — a placeholder for
    /// the eventual once-per-day rotation, deferred for now.
    @State private var lovedMemoriesShuffleSeed = UInt64.random(in: .min ... .max)
    /// Same purpose as `lovedMemoriesShuffleSeed`, kept separate so the two rails don't reshuffle
    /// in lockstep with each other.
    @State private var tripsShuffleSeed = UInt64.random(in: .min ... .max)
    /// Cached results of `computeHeroMemory()`/`computeHomeLovedMemories(excludingHeroID:)` —
    /// recomputed only by `refreshDisplayedMemories()` (after a real load, or a background-scan
    /// refresh), not on every body re-evaluation. Both do a `Calendar`-heavy pass over every loved/
    /// auto-memory Event (no longer capped — see `loadMemoryEvents()`); as a live computed property
    /// this reran on every single render (including ones triggered by an unrelated surgical update
    /// like a place-name resolve), which is what made Home's initial load and return-from-Memory
    /// feel like a freeze once the library had more than a handful of Memories.
    @State private var displayedHeroMemory: PhotoEvent?
    /// Chosen only once for this Home lifetime. A fresh app launch gives the same Hero Memory a
    /// different visual cover, while ordinary state refreshes never make the Hero flicker.
    @State private var displayedHeroCoverAssetID: String?
    @State private var displayedLovedMemories: [PhotoEvent] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NiziHomeHeader { selectTab(.diagnostics) }

                    if let displayedHeroMemory {
                        lovedMemoryHero(displayedHeroMemory)
                    }

                    lovedMemoriesSection
                    backgroundScanNudgeSection
                    latestMemorySection
                    moveImportEntry
                    tripsPreviewSection
                    eventDiscoveryLink

                    if albums.isEmpty {
                        emptyTimeline
                    } else {
                        albumPreviewSection
                    }
                }
            }
            .background(HomeSurfaceStyle.background)
            .safeAreaInset(edge: .bottom) {
                NiziBottomTabBar(
                    selected: .home,
                    onHome: { selectTab(.home) },
                    onEvents: { selectTab(.events) },
                    onTrips: { selectTab(.trips) },
                    onPhotobooks: { selectTab(.photobooks) }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            // Home is the NavigationStack root, so an edge-pop recognizer has nothing valid to
            // pop here. UIKit can otherwise retain its first-touch tracking after a push/pop even
            // though this screen has no back destination. The bridge disables it only while Home
            // is visible and restores the prior value before any pushed screen appears.
            .background {
                HomeRootInteractivePopGuard()
                    .allowsHitTesting(false)
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .events:
                    EventListView(onEventUpdated: { updated in
                        updateMemoryEventLocally(updated)
                    }, onSelectTab: selectTab)
                case .trips:
                    TripsListView(onSelectTab: selectTab)
                case .photobooks:
                    AlbumsListView(onSelectTab: selectTab)
                case .diagnostics:
                    PhotoLibraryDiagnosticsView(onSelectTab: selectTab)
                case .backgroundScan:
                    UserScanProgressView(scope: .fullLibrary) { _ in
                        if !navigationPath.isEmpty { navigationPath.removeLast() }
                    }
                }
            }
            .sheet(isPresented: $isMoveImportPresented) {
                NiziMoveImportView(modelContainer: modelContext.container)
            }
            .environment(\.albumPhotoProvider, albumPhotoProvider)
            .task {
                backgroundScanCoordinator.resumeBackgroundScanIfNeeded(scope: .fullLibrary)
                await loadStats()
                await loadAlbums()
                await loadMemoryEvents()
                await loadTrips()
                refreshDisplayedMemories()
            }
            // Do not refresh Home's collections merely because a pushed detail screen is popped.
            // That state write rebuilt the large Hero/Loved rail while the Trip rail was becoming
            // tappable again, which could invalidate the first interaction after returning. Love
            // actions performed on Home already update `memoryEvents` locally; an actual scan
            // result still refreshes through `discoveryRefreshToken` below.
            .onChange(of: backgroundScanCoordinator.discoveryRefreshToken) {
                Task {
                    await loadStats()
                    await loadMemoryEvents()
                    await loadTrips()
                    refreshDisplayedMemories()
                }
            }
        }
    }

    private var moveImportEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeRailHeading("Nhập ảnh")
                .padding(.horizontal, 24)

            Button {
                isMoveImportPresented = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(HomeSurfaceStyle.accent)
                    Text("Quét mã Nizi Move hoặc dán liên kết Google Drive.")
                        .font(.subheadline)
                        .foregroundStyle(HomeSurfaceStyle.mutedText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(HomeSurfaceStyle.mutedText)
                }
                .padding(18)
                .background(NiziPinterestTheme.surfaceCard, in: RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous)
                        .stroke(NiziPinterestTheme.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
        .padding(.top, HomeRailLayout.sectionSpacing)
    }

    /// § user request — Home, Events, Trips, Photobook, and Diagnostics behave like tabs: no back
    /// button, one shared bottom bar, and switching between them is instant (no push/pop slide).
    /// Every one of those 5 screens is pushed onto this SAME `navigationPath`, so replacing the
    /// whole path with a single-element array (rather than appending) both jumps directly to the
    /// target regardless of how deep the tap originated from and keeps the stack from growing
    /// unbounded across repeated tab switches, since there is no back button to unwind it with.
    /// `disablesAnimations` suppresses `NavigationStack`'s normal slide transition for this
    /// programmatic path change — this is a tab switch, not a drill-in push.
    private func selectTab(_ tab: NiziBottomTabBar.Tab) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch tab {
            case .home:
                navigationPath = NavigationPath()
            case .events:
                navigationPath = NavigationPath([HomeRoute.events])
            case .trips:
                navigationPath = NavigationPath([HomeRoute.trips])
            case .photobooks:
                navigationPath = NavigationPath([HomeRoute.photobooks])
            case .diagnostics:
                navigationPath = NavigationPath([HomeRoute.diagnostics])
            }
        }
    }

    /// Nudge card for "Dừng lại, xem ngay" — visible only while a background scan continuation
    /// still has real work left (`BackgroundScanStatus.hasIncompleteWork`). Tapping it prioritizes
    /// the remaining scan and opens the same progress screen the user skipped out of earlier.
    @ViewBuilder
    private var backgroundScanNudgeSection: some View {
        if backgroundScanCoordinator.hasIncompleteBackgroundScan {
            VStack(alignment: .leading, spacing: 12) {
                Text("home.background_scan.eyebrow")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(HomeSurfaceStyle.mutedText)

                Button {
                    backgroundScanCoordinator.prioritizeRemainingScan(scope: .fullLibrary)
                    navigationPath.append(HomeRoute.backgroundScan)
                } label: {
                    backgroundScanNudgeCard
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, HomeRailLayout.sectionSpacing)
        }
    }

    private var backgroundScanNudgeCard: some View {
        HStack(spacing: 16) {
            Text(localizedString(
                "home.background_scan.message",
                defaultValue: "You still have \(backgroundScanCoordinator.remainingPhotoCount) photos left to survey — don't miss out."
            ))
            .font(.onboardingSerif(size: 18, weight: .medium))
            .foregroundStyle(HomeSurfaceStyle.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeSurfaceStyle.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(NiziPinterestTheme.surfaceCard, in: RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous)
                .stroke(NiziPinterestTheme.hairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
    }

    /// The newest Memories by their photo/Event date, while still surfacing a newly imported
    /// Memory whose original photos were taken long ago.
    @ViewBuilder
    private var latestMemorySection: some View {
        if !recentCreatedMemories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeRailHeading(localizedString("home.latest_memory.eyebrow", defaultValue: "Latest Memories"))
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: HomeRailLayout.cardSpacing) {
                        ForEach(recentCreatedMemories) { event in
                            NavigationLink {
                                MemoryDetailView(
                                    event: event,
                                    onEventUpdated: { updated in updateMemoryEventLocally(updated) },
                                    onEventDeleted: { deletedID in removeMemoryEventLocally(deletedID) }
                                )
                            } label: {
                                RecentMemoryCard(event: event, assetProvider: homeThumbnailProvider)
                                    .contentShape(RoundedRectangle(cornerRadius: HomeRailLayout.recentCornerRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 24, for: .scrollContent)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            }
            .padding(.top, HomeRailLayout.sectionSpacing)
        }
    }

    private var recentCreatedMemories: [PhotoEvent] {
        Array(memoryEvents.sorted { recentRank(for: $0) > recentRank(for: $1) }.prefix(5))
    }

    /// Normal Events retain their date-based place in “Gần đây”. An imported Event receives its
    /// creation timestamp as an additional recency signal, so old EXIF dates never hide a Memory
    /// the user has just brought into Nizi.
    private func recentRank(for event: PhotoEvent) -> Date {
        max(event.startDate, event.createdAt)
    }

    private var eventDiscoveryLink: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeRailHeading("Recent")

            NavigationLink(value: HomeRoute.events) {
                eventDiscoveryCard
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, HomeRailLayout.sectionSpacing)
    }

    private var eventDiscoveryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Nizi đã tìm thấy \(eventCount) sự kiện.")
                    .font(.onboardingSerif(size: 20, weight: .medium))
                    .foregroundStyle(HomeSurfaceStyle.primaryText)
                Text("Hãy xem và lưu lại những kỷ niệm đáng nhớ.")
                    .font(.subheadline)
                    .foregroundStyle(HomeSurfaceStyle.mutedText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeSurfaceStyle.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(NiziPinterestTheme.surfaceCard, in: RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous)
                .stroke(NiziPinterestTheme.hairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var lovedMemoriesSection: some View {
        if !displayedLovedMemories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeRailHeading("Loved Memories")
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HomeRailLayout.cardSpacing) {
                        ForEach(displayedLovedMemories) { event in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    MemoryDetailView(
                                        event: event,
                                        onEventUpdated: { updated in updateMemoryEventLocally(updated) },
                                        onEventDeleted: { deletedID in removeMemoryEventLocally(deletedID) }
                                    )
                                } label: {
                                    LovedMemoryCard(event: event, assetProvider: homeThumbnailProvider)
                                        .contentShape(RoundedRectangle(cornerRadius: HomeRailLayout.lovedCornerRadius, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                // A pure Auto Memory (not yet loved by the user) shows an empty
                                // heart — tapping it adds a Love; it never auto-lights merely
                                // because it was selected by the system.
                                Button {
                                    Task { await setLoved(event, isLoved: !event.isLoved) }
                                } label: {
                                    Image(systemName: event.isLoved ? "heart.fill" : "heart")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(event.isLoved ? Color.red : .white)
                                        .frame(width: 34, height: 34)
                                        .background(.black.opacity(0.3), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(event.isLoved ? "Bỏ yêu thích sự kiện" : "Yêu thích sự kiện")
                                .padding(8)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 24, for: .scrollContent)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
            }
            .padding(.top, HomeRailLayout.sectionSpacing)
        }
    }

    /// Recomputes both the Hero and rail selection once, after a real load — see
    /// `displayedHeroMemory`/`displayedLovedMemories`'s own doc comment for why this isn't a live
    /// computed property.
    private func refreshDisplayedMemories() {
        let hero = computeHeroMemory()
        if displayedHeroMemory?.id != hero?.id || displayedHeroCoverAssetID == nil {
            displayedHeroCoverAssetID = hero?.assetIDs.randomElement() ?? hero?.coverAssetID
        }
        displayedHeroMemory = hero
        displayedLovedMemories = computeHomeLovedMemories(excludingHeroID: hero?.id)
    }

    /// Home is a taste, not the full archive. Excludes anything already surfaced inside a Trip —
    /// § user request "Loved Memories chỉ hiện memory không có trong Trips" — and the Hero's own
    /// event, never duplicated here. The pick itself is a random sample for now (a placeholder for
    /// the eventual once-per-day rotation, deferred separately); the seed is fixed per session so
    /// re-renders don't reshuffle the rail, only a fresh app launch does.
    private func computeHomeLovedMemories(excludingHeroID heroID: PhotoEvent.ID?) -> [PhotoEvent] {
        let tripEventIDs = Set(tripSummaries.flatMap(\.eventIDs))
        let pool = memoryEvents.filter { $0.id != heroID && !tripEventIDs.contains($0.id) }
        var rng = SeededGenerator(seed: lovedMemoriesShuffleSeed)
        return Array(pool.shuffled(using: &rng).prefix(6))
    }

    /// § user request — for now, the Hero is whichever Memory's date falls closest to today's
    /// month/day, restricted to *past* years ("của một trong các năm trước") — a recent photo from
    /// this year would otherwise always trivially "win" (near-zero day distance) and this would
    /// just silently reproduce the old newest-first pick. Falls back to the newest Memory overall
    /// when the library has no photo from any earlier year yet.
    private func computeHeroMemory() -> PhotoEvent? {
        guard !memoryEvents.isEmpty else { return nil }
        let calendar = Calendar.current
        let today = calendar.dateComponents([.year, .month, .day], from: .now)
        guard let todayYear = today.year, let todayMonth = today.month, let todayDay = today.day else {
            return memoryEvents.first
        }
        let pastYearEvents = memoryEvents.filter { calendar.component(.year, from: $0.startDate) < todayYear }
        guard !pastYearEvents.isEmpty else { return memoryEvents.first }
        return pastYearEvents.min {
            Self.dayOfYearDistance(from: $0.startDate, toMonth: todayMonth, day: todayDay)
                < Self.dayOfYearDistance(from: $1.startDate, toMonth: todayMonth, day: todayDay)
        }
    }

    /// Circular day-of-year distance (wraps across the Dec→Jan boundary, so Dec 30 reads as close
    /// to Jan 2, not ~363 days away) between `date`'s month/day and a given month/day, projected
    /// onto one fixed non-leap reference year so only the month/day component is compared.
    private static func dayOfYearDistance(from date: Date, toMonth month: Int, day: Int) -> Int {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.month, .day], from: date)
        guard let eventMonth = comps.month, let eventDay = comps.day,
              let eventReference = calendar.date(from: DateComponents(year: 2001, month: eventMonth, day: eventDay)),
              let todayReference = calendar.date(from: DateComponents(year: 2001, month: month, day: day))
        else { return .max }
        let diff = abs(calendar.dateComponents([.day], from: eventReference, to: todayReference).day ?? .max)
        return min(diff, 365 - diff)
    }

    private func lovedMemoryHero(_ event: PhotoEvent) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                MemoryDetailView(
                    event: event,
                    onEventUpdated: { updated in updateMemoryEventLocally(updated) },
                    onEventDeleted: { deletedID in removeMemoryEventLocally(deletedID) }
                )
            } label: {
                LovedMemoryCard(
                    event: event,
                    isHero: true,
                    assetProvider: homeThumbnailProvider,
                    coverAssetID: displayedHeroCoverAssetID
                )
                    .contentShape(RoundedRectangle(cornerRadius: NiziPinterestTheme.largeCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Task { await setLoved(event, isLoved: !event.isLoved) }
            } label: {
                Image(systemName: event.isLoved ? "heart.fill" : "heart")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(event.isLoved ? Color.red : .white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.isLoved ? "Bỏ yêu thích sự kiện" : "Yêu thích sự kiện")
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// Home only ever shows a taste of the Trips — the 5 newest (`fetchTrips()` already sorts
    /// newest-`startDate`-first) plus a trailing in-row route to `TripsListView`. Read-only:
    /// never re-runs Trip Discovery/Event Discovery/reverse-geocoding.
    @ViewBuilder
    private var tripsPreviewSection: some View {
        if !tripSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeRailHeading(localizedString("home.trips_preview.title", defaultValue: "Trips"))
                    .padding(.horizontal, 24)

                // Intentionally a plain horizontal scroll while tap behavior is being verified.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: HomeRailLayout.cardSpacing) {
                        ForEach(tripSummaries) { trip in
                            NavigationLink {
                                TripDetailView(trip: trip) { placeName in
                                    updateTripPlaceLocally(tripID: trip.id, placeName: placeName)
                                }
                            } label: {
                                TripMiniCard(trip: trip, assetProvider: homeThumbnailProvider)
                                    // The label's hit target must be the visible card rectangle,
                                    // not an aspect-fill cover image's larger render canvas.
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        // A value-based push (not `NavigationLink { TripsListView() }`) — this
                        // must go through the same tracked `navigationPath`/`HomeRoute` as the
                        // bottom bar's own tab switch. An anonymous push here left the tab bar
                        // unable to reconcile the stack afterward (§ user report: "vào Trip List
                        // từ home mà không qua menu thì không quay ra được, menu không nhận").
                        NavigationLink(value: HomeRoute.trips) {
                            TripsSeeAllTile()
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 24, for: .scrollContent)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
            }
            .padding(.top, HomeRailLayout.sectionSpacing)
        }
    }

    private func loadTrips() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            let trips = try await store.fetchTrips()
            let summaries = try await TripSummaryBuilder.makeSummaries(trips: trips, eventRepository: store)
            // § user request — random sample like Loved Memories, not just the newest 5. Same
            // seeded-shuffle trick: fixed once per app session so re-renders/surgical updates
            // (place-name resolve) don't reshuffle the rail, only a fresh app launch does.
            var rng = SeededGenerator(seed: tripsShuffleSeed)
            tripSummaries = Array(summaries.shuffled(using: &rng).prefix(5))
        } catch {
            NiziLogger.discovery.error("home_trips_load_failed")
        }
    }

    private func updateTripPlaceLocally(tripID: UUID, placeName: String) {
        guard let index = tripSummaries.firstIndex(where: { $0.id == tripID }) else { return }
        tripSummaries[index].primaryPlaceName = placeName
    }

    /// Home only ever shows a short taste of the Albums (§ layout request: moved the full list out
    /// to its own `AlbumsListView` page) — the 6 most recent (`SwiftDataAlbumDraftStore.
    /// fetchAllDrafts()` already sorts newest-`createdAt`-first) in one horizontal-scrolling row of
    /// compact `AlbumMiniCard`s and one trailing entry to the full Photobook archive.
    private var albumPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeRailHeading("Photobook")
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: HomeRailLayout.cardSpacing) {
                    ForEach(homeAlbumPreview) { album in
                        NavigationLink {
                            AlbumDetailView(draft: album) { updated in
                                await saveUpdatedAlbum(updated)
                            } onDelete: {
                                await loadAlbums()
                            }
                        } label: {
                            AlbumMiniCard(
                                album: cardSample(for: album),
                                assetProvider: photobookThumbnailProvider
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Value-based push, same reasoning as the Trips "see all" tile above.
                    NavigationLink(value: HomeRoute.photobooks) {
                        AlbumSeeAllTile()
                    }
                    .buttonStyle(.plain)
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
        }
        .padding(.top, HomeRailLayout.sectionSpacing)
        .padding(.bottom, HomeRailLayout.sectionSpacing)
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
        .padding(.horizontal, 24)
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

    private func loadMemoryEvents() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            // § user request — "các event mà auto-memory cũng tự động được thành loved memory":
            // catches up any Event that already qualifies as Auto Memory but hasn't been through
            // the seeding logic yet, before `fetchMemoryEvents` reads `isLoved` below.
            try await store.backfillAutoMemorySeeding()
            // Fetch every loved/auto-memory Event, not just a top-N slice: `homeLovedMemories`
            // excludes anything already in a Trip, so truncating here first could leave it with
            // too few candidates to fill a 6-card rail even when plenty of non-Trip memories
            // exist further down the list. `heroMemory`/`homeLovedMemories` do their own capping.
            memoryEvents = try await store.fetchMemoryEvents()
        } catch {
            NiziLogger.discovery.error("home_memory_events_load_failed")
        }
    }

    private func updateMemoryEventLocally(_ updated: PhotoEvent) {
        if let index = memoryEvents.firstIndex(where: { $0.id == updated.id }) {
            memoryEvents[index] = updated
        }
        // Patch the cached selection in place too — it's a separate snapshot now (see
        // `refreshDisplayedMemories()`), not a live re-derivation of `memoryEvents`.
        if displayedHeroMemory?.id == updated.id {
            displayedHeroMemory = updated
        }
        if let index = displayedLovedMemories.firstIndex(where: { $0.id == updated.id }) {
            displayedLovedMemories[index] = updated
        }
    }

    private func removeMemoryEventLocally(_ deletedID: PhotoEvent.ID) {
        memoryEvents.removeAll { $0.id == deletedID }
        displayedLovedMemories.removeAll { $0.id == deletedID }
        if displayedHeroMemory?.id == deletedID {
            displayedHeroMemory = nil
            displayedHeroCoverAssetID = nil
        }
    }

    /// § user report — "tab vào icon trái tim thấy phản ứng chậm, không nhạy": this used to
    /// `await` the SwiftData write (actor hop + fetch + save) *before* touching any local state,
    /// so the heart/card only updated once that round-trip finished. Optimistic-updates first —
    /// see `EventListView.toggleLove`'s own doc comment for the same fix there. A removal
    /// (unloving) can't be cleanly "un-removed" in place on failure, so the failure path just
    /// resyncs from what's actually persisted instead of guessing.
    private func setLoved(_ event: PhotoEvent, isLoved: Bool) async {
        // § user request — "Khi user đã uncheck thì điều kiện Automemory không tác dụng":
        // Auto Memory only ever seeds `isLoved` once, the first time an Event qualifies (see
        // `SwiftDataMemoryDiscoveryStore.replaceRebuildableEvents`'s own doc comment) — from
        // then on `isLoved` alone decides "is this a Memory," including here, so un-hearting
        // always drops the card (this replaces the previous SPRINT-NEXT § 17 behavior, which
        // kept a pure Auto Memory around after an unlove; the user has since reversed that).
        if !isLoved {
            withAnimation(.easeInOut(duration: 0.2)) {
                memoryEvents.removeAll { $0.id == event.id }
                if displayedHeroMemory?.id == event.id { displayedHeroMemory = nil }
                displayedLovedMemories.removeAll { $0.id == event.id }
            }
        } else {
            if let index = memoryEvents.firstIndex(where: { $0.id == event.id }) {
                memoryEvents[index].isLoved = isLoved
            }
            if displayedHeroMemory?.id == event.id { displayedHeroMemory?.isLoved = isLoved }
            if let index = displayedLovedMemories.firstIndex(where: { $0.id == event.id }) {
                displayedLovedMemories[index].isLoved = isLoved
            }
        }
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            try await store.setEventLoved(eventID: event.id, isLoved: isLoved)
        } catch {
            NiziLogger.discovery.error("home_memory_event_update_failed")
            await loadMemoryEvents()
            refreshDisplayedMemories()
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

/// Deterministic xorshift64 PRNG — lets `homeLovedMemories` shuffle the same way every time it's
/// recomputed for a given seed, instead of `Array.shuffled()`'s system RNG reshuffling on every
/// single body re-evaluation (which would make the rail's cards visibly change on every render).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

private enum HomeSurfaceStyle {
    static let background = NiziPinterestTheme.surfaceSoft
    static let primaryText = NiziPinterestTheme.ink
    static let mutedText = NiziPinterestTheme.mutedText
    static let accent = NiziPinterestTheme.primary
}

private enum HomeRailLayout {
    static let cardSpacing: CGFloat = 20
    static let sectionSpacing: CGFloat = 48
    static let lovedCornerRadius: CGFloat = 24
    static let recentCornerRadius: CGFloat = 28
}

private struct HomeRailHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.capitalized)
            .font(.onboardingSerif(size: 24, weight: .medium))
            .foregroundStyle(HomeSurfaceStyle.primaryText)
    }
}

/// Disables UIKit's interactive-pop recognizer only for Home, the root of this NavigationStack.
/// `viewWillDisappear` restores the exact former setting so Event/Trip/Album detail screens keep
/// their normal edge-swipe-back behavior.
private struct HomeRootInteractivePopGuard: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GuardController {
        GuardController()
    }

    func updateUIViewController(_ uiViewController: GuardController, context: Context) {}

    final class GuardController: UIViewController {
        private weak var guardedNavigationController: UINavigationController?
        private var previousGestureEnabled: Bool?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            disableRootInteractivePopGesture()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restoreInteractivePopGesture()
        }

        deinit {
            restoreInteractivePopGesture()
        }

        private func disableRootInteractivePopGesture() {
            guard previousGestureEnabled == nil else { return }
            guard let hostNavigationController = self.navigationController ?? parent?.navigationController,
                  let rootViewController = hostNavigationController.viewControllers.first,
                  hostNavigationController.topViewController === rootViewController
            else { return }

            guardedNavigationController = hostNavigationController
            previousGestureEnabled = hostNavigationController.interactivePopGestureRecognizer?.isEnabled
            hostNavigationController.interactivePopGestureRecognizer?.isEnabled = false
        }

        private func restoreInteractivePopGesture() {
            guard let navigationController = guardedNavigationController,
                  let previousGestureEnabled
            else { return }
            navigationController.interactivePopGestureRecognizer?.isEnabled = previousGestureEnabled
            self.previousGestureEnabled = nil
            guardedNavigationController = nil
        }
    }
}

/// One compact Album tile for `HomeView.albumPreviewSection`'s horizontal row — same real
/// cover-photo pipeline `AlbumDesignCard` uses, just a fraction of its size (§ layout request:
/// "kích thước nhỏ hơn Album hiện tại" — the full-size `AlbumDesignCard` now only appears on the
/// dedicated `AlbumsListView`).
private struct AlbumMiniCard: View {
    let album: AlbumCardSample
    let assetProvider: PhotoAssetProvider
    private let width: CGFloat = 180
    private let height: CGFloat = 270

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            coverImage
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(localizedString("album.photosCount", defaultValue: "\(album.photoCount) photos"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            .padding(14)
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: HomeRailLayout.lovedCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var coverImage: some View {
        ZStack {
            Group {
                if let coverPhoto = album.coverPhoto {
                    PhotobookThumbnail(
                        assetID: coverPhoto.sourceIdentifier,
                        assetProvider: assetProvider,
                        // Match Memory/Trip's quality-first display tier. `fastFormat` at 256px
                        // was adequate as a placeholder but visibly soft once rendered as a
                        // cover; this 400px high-quality tier remains cached across Home renders.
                        targetSize: CGSize(width: 400, height: 400)
                    )
                } else {
                    ZStack {
                        Color(.tertiarySystemFill)
                        Image(systemName: album.imageName)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(width * 0.28)
                    }
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
        }
        .frame(width: width, height: height)
    }
}

/// A thumbnail-only cover renderer for Home's tiny Photobook rail. It deliberately has no
/// ProgressView: rebuilding a horizontal lazy cell must leave the old image/cache result visible
/// or show a neutral placeholder, never flash a loading indicator.
private struct PhotobookThumbnail: View {
    let assetID: String
    let assetProvider: PhotoAssetProvider
    let targetSize: CGSize

    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: requestKey) {
            image = assetProvider.cachedThumbnail(
                assetID: assetID, targetSize: targetSize, contentMode: .fill
            )
            guard image == nil else { return }
            do {
                // Routed through the bounded loader like every other Home rail — a direct
                // `assetProvider.requestThumbnail` call runs PhotoKit's synchronous asset lookup
                // on whatever actor called it (MainActor, for a SwiftUI `.task`), which is exactly
                // the main-thread stall already fixed for Trip/Memory covers.
                image = try await PhotoThumbnailRequestLoader.shared.thumbnail(
                    assetID: assetID,
                    targetSize: targetSize,
                    contentMode: .fill,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality
                )
            } catch is CancellationError {
                // The cell simply left the horizontal viewport.
            } catch {
                NiziLogger.discovery.notice("home_photobook_thumbnail_unavailable")
            }
        }
    }

    private var requestKey: String {
        "\(assetID)-\(Int(targetSize.width))x\(Int(targetSize.height))"
    }
}

/// A vertically framed, snap-aligned card for Home's five-item Recent Memories rail.
private struct RecentMemoryCard: View {
    let event: PhotoEvent
    let assetProvider: PhotoAssetProvider
    @State private var coverImage: PlatformImage?
    @State private var isCoverSharp = false
    private static let placeholderSize = CGSize(width: 40, height: 40)
    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 400
    private var targetSize: CGSize { CGSize(width: cardWidth * 2, height: cardHeight * 2) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: cardWidth, height: cardHeight)
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .blur(radius: isCoverSharp ? 0 : 14)
                    .animation(.easeInOut(duration: 0.35), value: isCoverSharp)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .frame(width: cardWidth, height: cardHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.onboardingSerif(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(metadata)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(20)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: HomeRailLayout.recentCornerRadius, style: .continuous))
        .task(id: event.coverAssetID) {
            isCoverSharp = false
            guard let coverAssetID = event.coverAssetID else { return }
            if let cached = assetProvider.cachedThumbnail(
                assetID: coverAssetID, targetSize: targetSize, contentMode: .fill
            ) {
                coverImage = cached
                isCoverSharp = true
                return
            }

            if let placeholder = try? await PhotoThumbnailRequestLoader.shared.thumbnail(
                assetID: coverAssetID,
                targetSize: Self.placeholderSize,
                networkAccessAllowed: false,
                deliveryMode: .fast
            ) {
                coverImage = placeholder
            }

            do {
                let final = try await PhotoThumbnailRequestLoader.shared.thumbnail(
                    assetID: coverAssetID,
                    targetSize: targetSize,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality
                )
                coverImage = final
                isCoverSharp = true
            } catch {
                guard !(error is CancellationError) else { return }
                NiziLogger.discovery.error("home_latest_memory_cover_load_failed")
            }
        }
    }

    private var locationName: String {
        event.eventPlace?.displayName ?? event.primaryLocationLabel ?? event.titleSuggestion
    }

    private var title: String {
        localizedString("home.latest_memory.title", defaultValue: "Your latest memory")
    }

    private var metadata: String {
        "\(locationName) · \(event.startDate.formatted(.dateTime.day().month().year()))"
    }
}

/// Compact visual entry for a loved Event. It uses raw PhotoKit identifiers directly, matching
/// MemoryDetail's image pipeline rather than routing a non-Album photo through AlbumPhotoView.
private struct LovedMemoryCard: View {
    let event: PhotoEvent
    var isHero = false

    let assetProvider: PhotoAssetProvider
    /// The Hero supplies a per-app-launch choice from this Event's assets. Other cards use the
    /// Event's normal persisted cover.
    var coverAssetID: String? = nil
    @State private var coverImage: PlatformImage?
    /// `false` while `coverImage` is only the fast local placeholder (so the slot never sits
    /// empty during a slow iCloud download) — `true` once the real, right-sized image has loaded.
    /// Drives the blur below; kept separate from `coverImage == nil` since both states show *some*
    /// image, just at different quality.
    @State private var isCoverSharp = false
    private static let placeholderSize = CGSize(width: 40, height: 40)
    /// Hero dimensions never inherit an image's intrinsic size. The card stays inset from the
    /// canvas like a Pinterest feature card, so landscape imagery cannot widen Home's ScrollView.
    private var cardWidth: CGFloat { isHero ? UIScreen.main.bounds.width - 48 : 180 }
    private var cardHeight: CGFloat {
        isHero ? cardWidth * 1.5 : 270
    }
    private var targetSize: CGSize {
        CGSize(width: cardWidth * 2, height: cardHeight * 2)
    }
    private var textHorizontalPadding: CGFloat { isHero ? 24 : 14 }

    var body: some View {
        ZStack(alignment: isHero ? .bottom : .bottomLeading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: cardWidth, height: cardHeight)
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    // The fast placeholder is a tiny image stretched to fill the card, so it's
                    // necessarily soft — blur leans into that on purpose instead of showing
                    // upscaled blockiness, then eases to 0 once the real image is in.
                    .blur(radius: isCoverSharp ? 0 : 14)
                    .animation(.easeInOut(duration: 0.35), value: isCoverSharp)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .frame(width: cardWidth, height: cardHeight)

            VStack(alignment: isHero ? .center : .leading, spacing: isHero ? 6 : 4) {
                if isHero {
                    Text(relativeAge)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.75))
                        .textCase(.uppercase)
                    Text("Những kỷ niệm")
                        .font(.onboardingSerif(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(locationName)
                        .font(.onboardingSerif(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(heroDateRange)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                } else {
                    Text(event.eventPlace?.displayName ?? event.primaryLocationLabel ?? event.titleSuggestion)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(event.startDate.formatted(.dateTime.year()))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .multilineTextAlignment(isHero ? .center : .leading)
            .frame(
                width: cardWidth - textHorizontalPadding * 2,
                alignment: isHero ? .center : .leading
            )
            .frame(width: isHero ? cardWidth : nil, alignment: isHero ? .center : .leading)
            .padding(.leading, isHero ? 0 : textHorizontalPadding)
            .padding(.bottom, isHero ? 28 : textHorizontalPadding)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .bottomLeading)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: isHero ? NiziPinterestTheme.largeCornerRadius : HomeRailLayout.lovedCornerRadius, style: .continuous))
        .task(id: coverAssetID ?? event.coverAssetID) {
            isCoverSharp = false
            guard let coverAssetID = coverAssetID ?? event.coverAssetID else { return }
            if let cached = assetProvider.cachedThumbnail(
                assetID: coverAssetID, targetSize: targetSize, contentMode: .fill
            ) {
                coverImage = cached
                isCoverSharp = true
                return
            }

            // Fill the slot immediately with a tiny, local-only preview — PhotoKit keeps one for
            // every asset regardless of iCloud optimization, so this returns near-instantly even
            // for a photo whose full-quality version still needs a real download below.
            if let placeholder = try? await PhotoThumbnailRequestLoader.shared.thumbnail(
                assetID: coverAssetID,
                targetSize: Self.placeholderSize,
                contentMode: .fill,
                networkAccessAllowed: false,
                deliveryMode: .fast
            ) {
                coverImage = placeholder
            }

            do {
                let final = try await PhotoThumbnailRequestLoader.shared.thumbnail(
                    assetID: coverAssetID,
                    targetSize: targetSize,
                    contentMode: .fill,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality
                )
                coverImage = final
                isCoverSharp = true
            } catch {
                guard !(error is CancellationError) else { return }
                NiziLogger.discovery.error("home_loved_memory_cover_load_failed")
            }
        }
    }

    private var locationName: String {
        event.eventPlace?.displayName ?? event.primaryLocationLabel ?? event.titleSuggestion
    }

    private var relativeAge: String {
        let years = Calendar.current.dateComponents([.year], from: event.startDate, to: .now).year ?? 0
        return years > 0 ? "\(years) năm trước" : "Năm nay"
    }

    /// Home's anniversary Hero uses a compact, numeric date range so the remembered period is
    /// legible at a glance: “22-27/7/2022” for a same-month trip.
    private var heroDateRange: String {
        let calendar = Calendar.current
        let start = calendar.dateComponents([.day, .month, .year], from: event.startDate)
        let end = calendar.dateComponents([.day, .month, .year], from: event.endDate)
        guard let startDay = start.day, let startMonth = start.month, let startYear = start.year,
              let endDay = end.day, let endMonth = end.month, let endYear = end.year
        else {
            return event.startDate.formatted(.dateTime.day().month().year())
        }

        if startYear == endYear, startMonth == endMonth {
            return startDay == endDay
                ? "\(startDay)/\(startMonth)/\(startYear)"
                : "\(startDay)-\(endDay)/\(startMonth)/\(startYear)"
        }
        if startYear == endYear {
            return "\(startDay)/\(startMonth)-\(endDay)/\(endMonth)/\(startYear)"
        }
        return "\(startDay)/\(startMonth)/\(startYear)-\(endDay)/\(endMonth)/\(endYear)"
    }
}

/// A regular scroll-content header, intentionally not sticky.
private struct NiziHomeHeader: View {
    let onDiagnostics: () -> Void

    var body: some View {
        HStack {
            NiziBrandMark()
            Spacer()
            NiziSettingsMenu(onDiagnostics: onDiagnostics)
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
    }
}

struct NiziBrandMark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nizi")
                .font(.onboardingSerif(size: 27, weight: .medium))
            Text("Photo Memories")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(NiziPinterestTheme.mutedText)
        }
        .foregroundStyle(NiziPinterestTheme.ink)
    }
}

/// Shared settings menu for every primary destination. Account intentionally has no
/// action yet; language updates the persisted app-wide locale and the light theme is explicit.
struct NiziSettingsMenu: View {
    let onDiagnostics: () -> Void
    @AppStorage(NiziAppLanguage.storageKey) private var appLanguageRawValue: String = NiziAppLanguage.system.rawValue

    private var selectedLanguage: NiziAppLanguage {
        NiziAppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    var body: some View {
        Menu {
            Button {} label: {
                Label("Tài khoản — sắp có", systemImage: "person.circle")
            }
            .disabled(true)

            Menu {
                ForEach(NiziAppLanguage.allCases) { language in
                    Button {
                        appLanguageRawValue = language.rawValue
                    } label: {
                        if selectedLanguage == language {
                            Label(language.title, systemImage: "checkmark")
                        } else {
                            Text(language.title)
                        }
                    }
                }
            } label: {
                Label("Language", systemImage: "globe")
            }

            Menu {
                Label("Sáng", systemImage: "checkmark")
                Text("Tối sẽ sớm có")
            } label: {
                Label("Theme", systemImage: "circle.lefthalf.filled")
            }

            Divider()
            Button(action: onDiagnostics) {
                Label("Diagnostics", systemImage: "stethoscope")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NiziPinterestTheme.ink)
                .frame(width: 40, height: 40)
                .background(NiziPinterestTheme.surfaceCard, in: Circle())
        }
        .accessibilityLabel("Cài đặt")
    }
}

/// Fixed bottom navigation matching concept 4a: translucent blur, a subtle top divider, and a
/// cream active item. Each tab routes to the matching archive from the screen that owns it.
struct NiziBottomTabBar: View {
    enum Tab {
        case home
        case events
        case trips
        case photobooks
        case diagnostics
    }

    let selected: Tab
    let onHome: () -> Void
    let onEvents: () -> Void
    let onTrips: () -> Void
    let onPhotobooks: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            tab(systemImage: "house", label: "Home", isActive: selected == .home, action: onHome)
            tab(systemImage: "calendar", label: "Events", isActive: selected == .events, action: onEvents)
            tab(systemImage: "safari", label: "Trips", isActive: selected == .trips, action: onTrips)
            tab(systemImage: "book.closed", label: "Photobook", isActive: selected == .photobooks, action: onPhotobooks)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 0)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.48), .black.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tab(systemImage: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { tabLabel(systemImage: systemImage, label: label, isActive: isActive) }
        .buttonStyle(.plain)
        .frame(width: 56, height: 56)
        .background(isActive ? NiziPinterestTheme.primary : NiziPinterestTheme.surfaceCard, in: RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
        .accessibilityLabel(label)
    }

    private func tabLabel(systemImage: String, label: String, isActive: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isActive ? NiziPinterestTheme.canvas : HomeSurfaceStyle.primaryText)
    }
}

/// The trailing cell in `HomeView.tripsPreviewSection`'s row — sized to `TripMiniCard.cardWidth`
/// so it snaps and aligns exactly like every editorial Trip cover before it.
private struct TripsSeeAllTile: View {
    private let width: CGFloat = TripMiniCard.cardWidth
    private let height: CGFloat = TripMiniCard.cardHeight

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HomeRailLayout.lovedCornerRadius, style: .continuous)
                .fill(NiziPinterestTheme.surfaceCard)

            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "airplane")
                    .font(.system(size: 31, weight: .light))
                    .foregroundStyle(HomeSurfaceStyle.primaryText.opacity(0.8))

                Spacer()

                VStack(spacing: 5) {
                    Text("home.trips_preview.see_all")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(HomeSurfaceStyle.primaryText.opacity(0.88))
                .padding(.bottom, 18)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct AlbumSeeAllTile: View {
    private let width: CGFloat = 180
    private let height: CGFloat = 270

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30))
            Spacer()
            Text("home.album_preview.see_all")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
        }
        .foregroundStyle(HomeSurfaceStyle.primaryText)
        .padding(18)
        .frame(width: width, height: height, alignment: .leading)
        .background(NiziPinterestTheme.surfaceCard, in: RoundedRectangle(cornerRadius: HomeRailLayout.lovedCornerRadius, style: .continuous))
    }
}

#Preview {
    HomeView()
        .environment(BackgroundScanCoordinator())
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
