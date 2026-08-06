//
//  EventListView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// User-facing event list, reached only from Home's Quick Action card — never shown
/// directly after a scan. See docs/sprint/SPRINT-005-ADDENUM.md.
struct EventListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var allEvents: [PhotoEvent] = []
    /// § user request — "kết hợp thể hiện cả Memory vào": one screen, one list, toggled between
    /// two states by `lovedMemoriesToggle` (a single badge, not two separate tab chips — see its
    /// own doc comment). `.events` is the full archive (unchanged); `.memory` narrows to `isLoved`
    /// (see `isMemory(_:)`'s own doc comment for why `isAutoMemory` isn't part of this condition
    /// anymore) — the same rule `SwiftDataMemoryDiscoveryStore.fetchMemoryEvents()` already uses
    /// for Home's own "Kỷ niệm" rail, just computed from the list already in memory here rather
    /// than a second fetch.
    @State private var selectedTab: EventListTab = .events
    /// Events open on the current calendar year; the trailing "All" chip is an explicit opt-in
    /// to the complete history rather than the default.
    @State private var selectedYear: Int? = Calendar.current.component(.year, from: .now)
    @State private var selectedType: EventType?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSelectionMode = false
    /// Ordered by selection time so a merge has a deterministic source (first) and destination
    /// (second), while still rendering every selected Event as checked.
    @State private var selectedEventIDs: [PhotoEvent.ID] = []
    @State private var actionError: String?
    /// The grid's visible card identity is preserved across a detail push/pop. Keeping this
    /// separately from the data cache means filtering can still rebuild the grid deliberately.
    @State private var scrollAnchor: PhotoEvent.ID?
    /// A pushed detail keeps this view alive in the navigation stack. Do not refetch its full
    /// datasource when it becomes visible again — that invalidates SwiftUI's grid layout cache
    /// and returns the user to the first month.
    @State private var hasLoadedEvents = false
    /// The exact `UIImage` each `EventCardView` is currently displaying, reported back as
    /// soon as it loads — see the Hero-image follow-up. Read (not re-fetched) when a card is
    /// tapped, so `EventDetailView` never opens with a blank cover for an event whose card
    /// visibly already had one. Not a `NavigationPath`/Hashable concern here: this list still uses
    /// the inline `NavigationLink { destination } label: { }` form, so the destination closure can
    /// just read this directly — nothing needs to go through path-based navigation.
    @State private var loadedCoverImages: [PhotoEvent.ID: PlatformImage] = [:]

    private let assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    /// Lets Home reflect a love toggle made here on its own already-rendered rail card, in place —
    /// mirroring `TripDetailView`/`MemoryDetailView`'s `onPlaceResolved`/`onEventUpdated`. Home
    /// deliberately does not reload/re-render its rails on every appearance (see HomeView.swift's
    /// `.task`/`onChange` comments), so this is the only way a love change made here reaches Home.
    var onEventUpdated: (PhotoEvent) -> Void = { _ in }
    /// Home/Events/Trips/Photobook/Diagnostics act like tabs — this is `HomeView`'s single shared
    /// `navigationPath` mutator (see its own doc comment), threaded down so this screen's bottom
    /// bar jumps directly to another tab instead of nesting a fresh local push under itself.
    var onSelectTab: (NiziBottomTabBar.Tab) -> Void = { _ in }

    var body: some View {
        ScrollViewReader { scrollProxy in
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if allEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if filteredEvents.isEmpty {
                                emptyFilteredState
                            } else {
                                ForEach(monthSections) { section in
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(section.title)
                                            .font(.onboardingSerif(size: 24, weight: .medium))
                                            .foregroundStyle(EventArchiveStyle.primaryText)
                                            .padding(.top, 28)

                                        LazyVGrid(
                                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                                            spacing: 8
                                        ) {
                                            ForEach(section.events) { event in
                                                eventRow(event, scrollProxy: scrollProxy)
                                                    .id(event.id)
                                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                            }
                                        }
                                        .scrollTargetLayout()
                                    }
                                    .padding(.horizontal, 12)
                                }
                            }
                        } header: {
                            yearFilterHeader
                        }
                    }
                    .padding(.bottom, 36)
                }
                .scrollContentBackground(.hidden)
                .scrollPosition(id: $scrollAnchor, anchor: .top)
            }
        }
        .background(EventArchiveStyle.background)
        .navigationTitle("event.list.title")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(EventArchiveStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                lovedMemoriesToggle
                filterMenu
                Button(isSelectionMode ? "Xong" : "Chọn") {
                    isSelectionMode.toggle()
                    if !isSelectionMode { selectedEventIDs.removeAll() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedEventIDs.isEmpty {
                selectionActionBar(scrollProxy: scrollProxy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            NiziBottomTabBar(
                selected: .events,
                onHome: { onSelectTab(.home) },
                onEvents: {},
                onTrips: { onSelectTab(.trips) },
                onPhotobooks: { onSelectTab(.photobooks) }
            )
        }
        .navigationBarBackButtonHidden(true)
        .alert("Không thể cập nhật sự kiện", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("common.action.cancel", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { await loadEvents() }
        }
    }

    // Pulled out of `body` — inlined, this pushed the surrounding `ScrollView`/`LazyVStack`/
    // `ForEach` expression past what the type checker could resolve in reasonable time ("unable
    // to type-check this expression in reasonable time"), a known SwiftUI failure mode once a
    // `body` accumulates enough nested closures/generics. Splitting into a helper with an
    // explicit return type gives the compiler a much smaller expression to solve at a time.
    @ViewBuilder
    private func eventRow(_ event: PhotoEvent, scrollProxy: ScrollViewProxy) -> some View {
        // The iOS 18 `.zoom` navigation transition (Hero-style zoom from this card's cover into
        // the detail screen) was tried and reverted — it was inconsistent card to card even after
        // the underlying card-layout bugs were fixed, which points to a framework reliability
        // limit for this scenario rather than something fixable from this view. A plain push is
        // reliable every time, which matters more than the zoom flourish.
        //
        // The destination closure reads `loadedCoverImages` live, at the moment the user actually
        // taps — not a stale snapshot taken when this NavigationLink was constructed — so if the
        // card has already loaded its cover by then, the detail screen opens with it immediately.
        Group {
            if isSelectionMode {
                Button {
                    toggleSelection(of: event)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        eventArchiveRow(event)
                        selectionIndicator(isSelected: selectedEventIDs.contains(event.id))
                            .padding(8)
                    }
                }
            } else {
            ZStack(alignment: .topTrailing) {
                // § user request — "Nếu 1 event là loved-memory thì khi tap vào bên trong phải là
                // màn memory detail": a loved Event (`isMemory(_:)` — `isLoved`) opens the same
                // `MemoryDetailView` Home's own Loved Memories rail already pushes, instead of the
                // plain `EventDetailView`.
                NavigationLink {
                    if Self.isMemory(event) {
                        MemoryDetailView(
                            event: event,
                            onEventUpdated: { updated in updateEventLocally(updated) },
                            onEventDeleted: { deletedID in
                                await removeEventFromList(deletedID, scrollProxy: scrollProxy)
                            }
                        )
                    } else {
                        EventDetailView(
                            event: event, initialHeroImage: loadedCoverImages[event.id],
                            onEventDeleted: { deletedID in
                                await removeEventFromList(deletedID, scrollProxy: scrollProxy)
                            }
                        )
                    }
                } label: {
                    eventArchiveRow(event)
                }

                loveButton(for: event)
                    .padding(.trailing, 2)
            }
            }
        }
        .buttonStyle(.plain)
    }

    private func eventArchiveRow(_ event: PhotoEvent) -> some View {
        EventArchiveRow(
            event: event,
            assetProvider: assetProvider,
            onCoverLoaded: { loadedCoverImages[event.id] = $0 },
            onPlaceRequested: { event in
                Task { await resolvePlace(for: event) }
            }
        )
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : .clear)
            Circle()
                .stroke(isSelected ? Color.accentColor : .secondary, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
    }

    private func loveButton(for event: PhotoEvent) -> some View {
        Button {
            Task { await toggleLove(for: event) }
        } label: {
            Image(systemName: event.isLoved ? "heart.fill" : "heart")
                .font(.title3.weight(.semibold))
                .foregroundStyle(event.isLoved ? Color.red : Color.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.28), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(event.isLoved ? "Bỏ yêu thích sự kiện" : "Yêu thích sự kiện")
        .accessibilityHint("Chỉ thay đổi trạng thái yêu thích")
    }

    private func selectionActionBar(scrollProxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Button("Gộp events") {
                Task { await mergeSelectedEvents(scrollProxy: scrollProxy) }
            }
            .buttonStyle(.bordered)
            .disabled(selectedEventIDs.count < 2)

            Button("Xoá events") {
                Task { await deleteSelectedEvents() }
            }
            // Deliberately neutral: deletion already requires an explicit selection and tap.
            .buttonStyle(.bordered)
            .disabled(selectedEventIDs.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func toggleSelection(of event: PhotoEvent) {
        if let index = selectedEventIDs.firstIndex(of: event.id) {
            selectedEventIDs.remove(at: index)
        } else {
            selectedEventIDs.append(event.id)
        }
    }

    /// § user report — "tab vào icon trái tim thấy phản ứng chậm, không nhạy": this used to
    /// `await` the SwiftData write (actor hop + fetch + save — genuinely I/O-bound) *before*
    /// touching `allEvents`, so the heart only flipped once that round-trip finished. Updating
    /// local state first makes the tap feel instant; the persistence call still happens right
    /// after, and a failure rolls the optimistic change back instead of silently diverging from
    /// what's actually saved.
    private func toggleLove(for event: PhotoEvent) async {
        guard let index = allEvents.firstIndex(where: { $0.id == event.id }) else { return }
        let isLoved = !event.isLoved
        allEvents[index].isLoved = isLoved
        onEventUpdated(allEvents[index])
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            try await store.setEventLoved(eventID: event.id, isLoved: isLoved)
        } catch {
            if let revertIndex = allEvents.firstIndex(where: { $0.id == event.id }) {
                allEvents[revertIndex].isLoved = !isLoved
                onEventUpdated(allEvents[revertIndex])
            }
            actionError = "Không thể cập nhật sự kiện yêu thích. Vui lòng thử lại."
        }
    }

    /// Mirrors `HomeView.updateMemoryEventLocally` — `MemoryDetailView` reports back a Place it
    /// resolved or a photo it swapped, and both this list and Home (via the upward
    /// `onEventUpdated`) need to reflect it without a full reload.
    private func updateEventLocally(_ updated: PhotoEvent) {
        guard let index = allEvents.firstIndex(where: { $0.id == updated.id }) else { return }
        allEvents[index] = updated
        onEventUpdated(updated)
    }

    private func resolvePlace(for event: PhotoEvent) async {
        guard event.placeResolutionState == .unresolved else { return }
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
        let updated = await enrichPlaceIfNeeded(for: event, store: store)
        guard let index = allEvents.firstIndex(where: { $0.id == updated.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            allEvents[index] = updated
        }
    }

    /// Visibility + tab narrowing only — year/type filters apply on top in `filteredEvents`, and
    /// `availableYears` reads from this (not `allEvents`) so the year chips only ever offer years
    /// that actually have something in the *currently selected* tab.
    private var eventsInSelectedTab: [PhotoEvent] {
        allEvents.filter { event in
            Self.isVisibleInProductionList(event) && (selectedTab == .events || Self.isMemory(event))
        }
    }

    private var filteredEvents: [PhotoEvent] {
        eventsInSelectedTab
            .filter { event in
                (selectedYear == nil || Calendar.current.component(.year, from: event.startDate) == selectedYear)
                    && (selectedType == nil || event.eventType == selectedType)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    /// `.hiddenNoise` Events stay out of the production list by default (SPRINT-FAST-EVENT-
    /// QUALITY § 8) — Diagnostics reads the same repository unfiltered, so it still sees
    /// everything. Not `private` so it's directly testable without going through a `View`.
    static func isVisibleInProductionList(_ event: PhotoEvent) -> Bool {
        event.eventVisibility != .hiddenNoise
    }

    /// Same rule `SwiftDataMemoryDiscoveryStore.fetchMemoryEvents()` uses for Home's own "Kỷ
    /// niệm" rail — § user request "Automemory chỉ có tác dụng lúc đầu": `isAutoMemory` only ever
    /// seeds `isLoved` once, the first time an Event qualifies (see
    /// `replaceRebuildableEvents`'s own doc comment) — `isLoved` alone is the ongoing, fully
    /// user-owned answer to "is this a Memory," so un-hearting one always removes it here even
    /// though `isAutoMemory` itself keeps getting recomputed true on every rebuild. Not `private`
    /// for the same directly-testable reason as `isVisibleInProductionList`.
    static func isMemory(_ event: PhotoEvent) -> Bool {
        event.isLoved
    }

    private var availableYears: [Int] {
        Array(Set(eventsInSelectedTab.map { Calendar.current.component(.year, from: $0.startDate) })).sorted(by: >)
    }

    private var monthSections: [EventArchiveMonthSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEvents) { event in
            calendar.date(from: calendar.dateComponents([.year, .month], from: event.startDate)) ?? event.startDate
        }
        return grouped
            .map { month, events in
                EventArchiveMonthSection(
                    month: month,
                    events: events.sorted { $0.startDate > $1.startDate },
                    includesYear: selectedYear == nil
                )
            }
            .sorted { $0.month > $1.month }
    }

    /// § user request — "Badge Memory chuyển lên ngang hàng với Tiêu đề sự kiện, nhưng nằm bên
    /// phải... Badge sẽ dạng toggle. Ấn thì chuyển sang memory... ấn cái thì về all event. Bỏ
    /// badge Event đi": one toggle badge (not two separate tab chips anymore) living in the nav
    /// bar's own trailing toolbar group — level with the title, on the right — with a red heart
    /// that fills solid once active. Tapping it flips `selectedTab` between showing every Event
    /// (`.events`) and only loved ones (`.memory`, i.e. `isMemory(_:)`/`isLoved`); there is no
    /// third state and no separate "Events" control to tap back to — this same badge does both.
    private var lovedMemoriesToggle: some View {
        let isActive = selectedTab == .memory
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedTab = isActive ? .events : .memory
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isActive ? "heart.fill" : "heart")
                    .foregroundStyle(Color.red)
                Text("event.list.loved_toggle")
            }
            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? EventArchiveStyle.background : EventArchiveStyle.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isActive ? EventArchiveStyle.accent : NiziPinterestTheme.surfaceCard, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isActive
                ? localizedString("event.list.loved_toggle.accessibility.on", defaultValue: "Đang lọc theo kỷ niệm yêu thích")
                : localizedString("event.list.loved_toggle.accessibility.off", defaultValue: "Lọc theo kỷ niệm yêu thích")
        )
    }

    private var yearFilterHeader: some View {
        YearFilterBar(
            years: availableYears,
            selectedYear: $selectedYear,
            placesAllLast: true,
            selectedColor: EventArchiveStyle.accent
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(EventArchiveStyle.background)
    }

    private var filterMenu: some View {
        Menu {
            Picker("event.list.filter.type_field", selection: $selectedType) {
                Text("event.list.filter.all_types").tag(EventType?.none)
                Text(EventType.trip.displayLabel).tag(EventType?.some(.trip))
                Text(EventType.dayEvent.displayLabel).tag(EventType?.some(.dayEvent))
                Text(EventType.weekend.displayLabel).tag(EventType?.some(.weekend))
            }
        } label: {
            Label("event.list.filter.label", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("event.list.filter.accessibility")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("event.list.empty.title")
                .font(.headline)
            Text("event.list.empty.message")
                .font(.subheadline)
                .foregroundStyle(EventArchiveStyle.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyFilteredState: some View {
        VStack(spacing: 8) {
            switch selectedTab {
            case .events:
                Text("event.list.empty.title")
                    .font(.headline)
                Text("event.list.empty.message")
                    .font(.subheadline)
                    .foregroundStyle(EventArchiveStyle.mutedText)
            case .memory:
                // § user request — the generic "no events yet" copy is misleading here: plenty of
                // Events can exist while none have qualified as a Memory (`isAutoMemory`) or been
                // loved yet, which is the far more common empty case for this tab.
                Text("event.list.memory_tab.empty.title")
                    .font(.headline)
                Text("event.list.memory_tab.empty.message")
                    .font(.subheadline)
                    .foregroundStyle(EventArchiveStyle.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
            .foregroundStyle(EventArchiveStyle.mutedText)
                .multilineTextAlignment(.center)
            Button("common.action.retry") {
                Task { await loadEvents(force: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func loadEvents(force: Bool = false) async {
        guard force || !hasLoadedEvents else { return }
        isLoading = true
        errorMessage = nil
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            // § user request — "các event mà auto-memory cũng tự động được thành loved memory":
            // catches up any Event that already qualifies as Auto Memory but hasn't been through
            // the seeding logic yet, before this screen reads `isLoved` for the Memory toggle.
            try await store.backfillAutoMemorySeeding()
            allEvents = try await store.fetchEvents(sortedBy: .scoreDescending)
            hasLoadedEvents = true
            // Repair older one-level Vietnamese labels before/while the first viewport appears.
            // This bounded window deliberately avoids an app-wide reverse-geocoding pass.
            let candidates = Array(allEvents.prefix(12)).filter(needsVietnamesePlaceUpgrade)
            for event in candidates {
                Task { await resolvePlace(for: event) }
            }
        } catch {
            errorMessage = localizedString("event.list.error.load_failed", defaultValue: "Couldn't load the events list.")
        }
        isLoading = false
    }

    private func deleteSelectedEvents() async {
        let selected = selectedEventIDs.compactMap { id in allEvents.first(where: { $0.id == id }) }
        guard !selected.isEmpty else { return }

        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            for event in selected {
                try await store.deleteEvent(id: event.id)
            }
            await loadEvents(force: true)
            selectedEventIDs.removeAll()
        } catch {
            actionError = "Không thể xoá các sự kiện đã chọn. Vui lòng thử lại."
        }
    }

    /// Called by `EventDetailView` after its repository delete succeeds but before it pops. The
    /// preceding card becomes the persistent grid anchor (or the next card for the first item),
    /// so the still-mounted EventList returns at a meaningful neighbour rather than at the top.
    private func removeEventFromList(_ deletedID: PhotoEvent.ID, scrollProxy: ScrollViewProxy) async {
        let visibleEvents = filteredEvents
        guard let deletedIndex = visibleEvents.firstIndex(where: { $0.id == deletedID }) else { return }
        let returnAnchor = visibleEvents.prefix(deletedIndex).last?.id
            ?? visibleEvents.dropFirst(deletedIndex + 1).first?.id

        withAnimation(.easeInOut(duration: 0.3)) {
            // `scrollProxy.scrollTo` alone is unreliable while EventDetail still covers this
            // screen. The binding survives the pop and applies once the grid becomes visible.
            scrollAnchor = returnAnchor
            allEvents.removeAll { $0.id == deletedID }
            selectedEventIDs.removeAll { $0 == deletedID }
            loadedCoverImages.removeValue(forKey: deletedID)
        }
        guard let returnAnchor else { return }

        await Task.yield()
        // This gives immediate feedback when the source grid is still rendered (e.g. an iPad
        // split presentation); `scrollAnchor` above remains the authoritative restoration path.
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo(returnAnchor, anchor: .center)
        }
    }

    private func mergeSelectedEvents(scrollProxy: ScrollViewProxy) async {
        guard selectedEventIDs.count >= 2 else { return }
        // `filteredEvents` is newest-first, therefore its first selected Event is visually above
        // the others. Keep that row as the merge destination so its identity and on-screen
        // position survive the operation.
        let selected = filteredEvents.filter { selectedEventIDs.contains($0.id) }
        guard selected.count >= 2 else { return }
        let destination = selected[0]

        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            for source in selected.dropFirst() {
                try await store.mergeEvent(sourceID: source.id, into: destination.id)
            }
            let reloaded = try await store.fetchEvents(sortedBy: .scoreDescending)

            // One transaction lets the removed card fade/shrink while all following cards close
            // their gap and move upward, instead of abruptly rebuilding the full list.
            withAnimation(.easeInOut(duration: 0.35)) {
                allEvents = reloaded
                selectedEventIDs.removeAll()
            }
            await Task.yield()
            withAnimation(.easeOut(duration: 0.25)) {
                scrollProxy.scrollTo(destination.id, anchor: .top)
            }
        } catch {
            actionError = "Không thể gộp các sự kiện đã chọn. Vui lòng thử lại."
        }
    }
}

private enum EventListTab: CaseIterable {
    case events
    case memory

    /// The noun used by diagnostics and selection copy ("3 sự kiện" vs "3 kỷ niệm").
    var itemCountLabel: String {
        switch self {
        case .events: return localizedString("event.list.tab.events.item_count_label", defaultValue: "sự kiện")
        case .memory: return localizedString("event.list.tab.memory.item_count_label", defaultValue: "kỷ niệm")
        }
    }
}

private enum EventArchiveStyle {
    static let background = NiziPinterestTheme.surfaceSoft
    static let primaryText = NiziPinterestTheme.ink
    static let mutedText = NiziPinterestTheme.mutedText
    static let divider = NiziPinterestTheme.hairline
    static let accent = NiziPinterestTheme.primary
}

private struct EventArchiveMonthSection: Identifiable {
    let month: Date
    let events: [PhotoEvent]
    let includesYear: Bool

    var id: Date { month }

    var title: String {
        let format = includesYear ? "LLLL yyyy" : "LLLL"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = format
        return formatter.string(from: month).capitalized
    }
}

private struct EventArchiveRow: View {
    let event: PhotoEvent
    let assetProvider: PhotoAssetProvider
    let onCoverLoaded: (PlatformImage) -> Void
    let onPlaceRequested: (PhotoEvent) -> Void

    @State private var coverImage: PlatformImage?
    /// Explicit ownership is important here: a LazyVStack may keep rows alive briefly while the
    /// user flings through a long year. Cancelling at disappearance prevents those rows from
    /// continuing iCloud/PhotoKit work after they are no longer useful on screen.
    @State private var thumbnailTask: Task<Void, Never>?
    /// A three-column grid never renders an image wider than roughly 120pt on iPhone. Requesting
    /// a compact square thumbnail avoids decoding portrait-sized images for every visible cell.
    private static let thumbnailPixelSize = CGSize(width: 240, height: 240)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                NiziPinterestTheme.surfaceCard
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.eventPlace?.displayName ?? event.primaryLocationLabel ?? event.titleSuggestion)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(metadata)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
        .onAppear { startThumbnailLoad() }
        .onDisappear {
            thumbnailTask?.cancel()
            thumbnailTask = nil
        }
        .onChange(of: event.coverAssetID) { _, _ in
            thumbnailTask?.cancel()
            coverImage = nil
            startThumbnailLoad()
        }
        .task(id: event.placeResolutionState) {
            guard eventNeedsPlaceResolution(event) else { return }
            onPlaceRequested(event)
        }
    }

    private var metadata: String {
        "\(dateRange) · \(event.assetCount) ảnh"
    }

    private var dateRange: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        guard !calendar.isDate(event.startDate, inSameDayAs: event.endDate) else {
            return formatter.string(from: event.startDate)
        }
        if calendar.component(.month, from: event.startDate) == calendar.component(.month, from: event.endDate),
           calendar.component(.year, from: event.startDate) == calendar.component(.year, from: event.endDate) {
            let endMonth = DateFormatter()
            endMonth.locale = Locale(identifier: "en_US_POSIX")
            endMonth.dateFormat = "MMM"
            return "\(event.startDate.formatted(.dateTime.day()))–\(event.endDate.formatted(.dateTime.day())) \(endMonth.string(from: event.endDate))"
        }
        return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
    }

    private func startThumbnailLoad() {
        guard let assetID = event.coverAssetID else { return }
        // A cache hit is synchronous and free; do not issue a PhotoKit request in that case.
        coverImage = assetProvider.cachedThumbnail(
            assetID: assetID, targetSize: Self.thumbnailPixelSize, contentMode: .fill
        )
        guard coverImage == nil else { return }

        thumbnailTask?.cancel()
        thumbnailTask = Task {
            do {
                // List scrolling must never wait for an iCloud original. A local fast thumbnail
                // is enough for a 60pt row; the detail screen owns any higher-quality request.
                let image = try await assetProvider.requestThumbnail(
                    assetID: assetID,
                    targetSize: Self.thumbnailPixelSize,
                    networkAccessAllowed: false,
                    deliveryMode: .fast,
                    contentMode: .fill
                )
                guard !Task.isCancelled else { return }
                coverImage = image
                onCoverLoaded(image)
            } catch is CancellationError {
                // Expected while a fast scroll recycles this row.
            } catch {
                // iCloud-only assets intentionally remain as a lightweight placeholder here;
                // opening the Event is where network-backed imagery is allowed.
                NiziLogger.discovery.notice("event_archive_thumbnail_unavailable")
            }
        }
    }
}

#Preview {
    NavigationStack {
        EventListView()
    }
    .modelContainer(
        for: [MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self],
        inMemory: true
    )
}
