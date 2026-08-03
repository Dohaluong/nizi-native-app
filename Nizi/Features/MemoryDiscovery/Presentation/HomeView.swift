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
    @State private var displayedLovedMemories: [PhotoEvent] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    moveImportEntry
                    if let displayedHeroMemory {
                        lovedMemoryHero(displayedHeroMemory)
                    }

                    lovedMemoriesSection
                    backgroundScanNudgeSection
                    // § user request — a single big square "your latest memory" card takes the
                    // spot the Event-count summary card used to occupy; the Event entry itself
                    // moved below the Trips rail.
                    latestMemorySection
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
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) {
                NiziBottomTabBar(
                    selected: .home,
                    onHome: { selectTab(.home) },
                    onEvents: { selectTab(.events) },
                    onTrips: { selectTab(.trips) },
                    onPhotobooks: { selectTab(.photobooks) },
                    onDiagnostics: { selectTab(.diagnostics) }
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
            .preferredColorScheme(.dark)
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
        Button {
            isMoveImportPresented = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(HomeSurfaceStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nhập ảnh từ máy tính").font(.headline)
                    Text("Quét mã Nizi Move để chuyển ảnh vào Photos.").font(.subheadline).foregroundStyle(HomeSurfaceStyle.mutedText)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(HomeSurfaceStyle.mutedText)
            }
            .padding(18)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 28)
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
            .padding(.top, 30)
            .padding(.bottom, 8)
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Direct entry into the Events archive, displayed below the Loved Memories rail.
    /// § user request — a single big square card for whichever Memory was *created* most
    /// recently (`createdAt`, not `startDate`) — today that's just "whatever Nizi discovered
    /// last," but the spot is meant for a future auto-detected "you just got back from a trip"
    /// signal, so it's kept as its own section rather than folded into the Loved Memories rail.
    @ViewBuilder
    private var latestMemorySection: some View {
        if let event = latestCreatedMemory {
            VStack(alignment: .leading, spacing: 12) {
                Text("home.latest_memory.eyebrow")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(HomeSurfaceStyle.mutedText)

                NavigationLink {
                    MemoryDetailView(event: event) { updated in
                        updateMemoryEventLocally(updated)
                    }
                } label: {
                    LatestMemoryCard(event: event, assetProvider: homeThumbnailProvider)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 36)
        }
    }

    /// Not `tripEventIDs`-excluded like `homeLovedMemories` — this card answers "what's new,"
    /// independent of whether it happens to also belong to a Trip.
    private var latestCreatedMemory: PhotoEvent? {
        memoryEvents.max { $0.createdAt < $1.createdAt }
    }

    private var eventDiscoveryLink: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(HomeSurfaceStyle.mutedText)

            NavigationLink(value: HomeRoute.events) {
                eventDiscoveryCard
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 36)
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var lovedMemoriesSection: some View {
        if !displayedLovedMemories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("LOVED MEMORIES")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(HomeSurfaceStyle.mutedText)
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(displayedLovedMemories) { event in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    MemoryDetailView(event: event) { updated in
                                        updateMemoryEventLocally(updated)
                                    }
                                } label: {
                                    LovedMemoryCard(event: event, assetProvider: homeThumbnailProvider)
                                        .contentShape(Rectangle())
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
            .padding(.top, 36)
        }
    }

    /// Recomputes both the Hero and rail selection once, after a real load — see
    /// `displayedHeroMemory`/`displayedLovedMemories`'s own doc comment for why this isn't a live
    /// computed property.
    private func refreshDisplayedMemories() {
        let hero = computeHeroMemory()
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
                MemoryDetailView(event: event) { updated in
                    updateMemoryEventLocally(updated)
                }
            } label: {
                LovedMemoryCard(event: event, isHero: true, assetProvider: homeThumbnailProvider)
                    .contentShape(Rectangle())
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
            .padding(.top, 58)
            .padding(.trailing, 20)
        }
    }

    /// Home only ever shows a taste of the Trips — the 5 newest (`fetchTrips()` already sorts
    /// newest-`startDate`-first) plus a trailing in-row route to `TripsListView`. Read-only:
    /// never re-runs Trip Discovery/Event Discovery/reverse-geocoding.
    @ViewBuilder
    private var tripsPreviewSection: some View {
        if !tripSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("home.trips_preview.title")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(HomeSurfaceStyle.mutedText)
                    .padding(.horizontal, 24)

                // Intentionally a plain horizontal scroll while tap behavior is being verified.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 20) {
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
            .padding(.bottom, 44)
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
            Text("PHOTOBOOK")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(HomeSurfaceStyle.mutedText)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
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
        .padding(.bottom, 48)
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
    static let background = Color(red: 14 / 255, green: 13 / 255, blue: 16 / 255)
    static let primaryText = Color(red: 246 / 255, green: 241 / 255, blue: 234 / 255)
    static let mutedText = primaryText.opacity(0.45)
    static let accent = Color(red: 225 / 255, green: 135 / 255, blue: 91 / 255)
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
    private let size: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            coverImage
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomeSurfaceStyle.primaryText.opacity(0.78))
                    .lineLimit(1)
                Text(localizedString("album.photosCount", defaultValue: "\(album.photoCount) photos"))
                    .font(.system(size: 12))
                    .foregroundStyle(HomeSurfaceStyle.mutedText.opacity(0.82))
                    .lineLimit(1)
            }
        }
        .frame(width: size, alignment: .leading)
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
                            .padding(size * 0.28)
                    }
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

/// The big square card for `HomeView.latestMemorySection` — full-bleed square cover, same
/// two-tier placeholder-then-sharp image load every other Home card uses.
private struct LatestMemoryCard: View {
    let event: PhotoEvent
    let assetProvider: PhotoAssetProvider
    @State private var coverImage: PlatformImage?
    @State private var isCoverSharp = false
    private static let placeholderSize = CGSize(width: 40, height: 40)
    private var size: CGFloat { UIScreen.main.bounds.width - 48 }
    private var targetSize: CGSize { CGSize(width: size * 2, height: size * 2) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: size, height: size)
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .blur(radius: isCoverSharp ? 0 : 14)
                    .animation(.easeInOut(duration: 0.35), value: isCoverSharp)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .frame(width: size, height: size)

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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    @State private var coverImage: PlatformImage?
    /// `false` while `coverImage` is only the fast local placeholder (so the slot never sits
    /// empty during a slow iCloud download) — `true` once the real, right-sized image has loaded.
    /// Drives the blur below; kept separate from `coverImage == nil` since both states show *some*
    /// image, just at different quality.
    @State private var isCoverSharp = false
    private static let placeholderSize = CGSize(width: 40, height: 40)
    /// Hero dimensions never inherit an image's intrinsic size. An explicit screen-width canvas
    /// is what prevents a landscape image from widening Home's entire ScrollView.
    private var cardWidth: CGFloat { isHero ? UIScreen.main.bounds.width : 132 }
    private var cardHeight: CGFloat {
        isHero ? UIScreen.main.bounds.height * (700.0 / 874.0) : 172
    }
    private var targetSize: CGSize {
        CGSize(width: cardWidth * 2, height: cardHeight * 2)
    }
    private var textHorizontalPadding: CGFloat { isHero ? 24 : 10 }

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
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .frame(width: cardWidth, height: cardHeight)
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
        .clipShape(RoundedRectangle(cornerRadius: isHero ? 0 : 14, style: .continuous))
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
    let onDiagnostics: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(systemImage: "house", label: "Home", isActive: selected == .home, action: onHome)
            tab(systemImage: "calendar", label: "Events", isActive: selected == .events, action: onEvents)
            tab(systemImage: "safari", label: "Trips", isActive: selected == .trips, action: onTrips)
            tab(systemImage: "book.closed", label: "Photobook", isActive: selected == .photobooks, action: onPhotobooks)
            tab(systemImage: "stethoscope", label: "Diagnostics", isActive: selected == .diagnostics, action: onDiagnostics)
        }
        .frame(maxWidth: .infinity)
        // Fixed edge inset anchors the first/last tabs. Giving every tab the same flexible
        // column then spaces the two inner icons evenly, independent of label width.
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 0)
        .background {
            ZStack(alignment: .top) {
                Color(red: 20 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.85)
                Color.white.opacity(0.08).frame(height: 1)
            }
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tab(systemImage: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tabLabel(systemImage: systemImage, label: label, isActive: isActive)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func tabLabel(systemImage: String, label: String, isActive: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
            Text(label)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
        }
        .foregroundStyle(isActive ? HomeSurfaceStyle.primaryText : HomeSurfaceStyle.mutedText)
    }
}

/// The trailing cell in `HomeView.tripsPreviewSection`'s row — sized to `TripMiniCard.cardWidth`
/// so it snaps and aligns exactly like every editorial Trip cover before it.
private struct TripsSeeAllTile: View {
    private let width: CGFloat = TripMiniCard.cardWidth
    private let height: CGFloat = TripMiniCard.cardHeight

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.09))

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
                .foregroundStyle(HomeSurfaceStyle.mutedText.opacity(0.9))
                .lineLimit(2)
                .frame(width: size, alignment: .leading)
        }
        .frame(width: size, alignment: .leading)
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
