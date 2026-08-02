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
                                    VStack(alignment: .leading, spacing: 0) {
                                        // § user request — as big and clear a divider as the
                                        // Trips list's year headers.
                                        Text(section.title)
                                            .font(.onboardingSerif(size: 28, weight: .bold))
                                            .foregroundStyle(EventArchiveStyle.primaryText)
                                            .padding(.top, 22)
                                            .padding(.bottom, 10)

                                        ForEach(section.events) { event in
                                            eventRow(event, scrollProxy: scrollProxy)
                                                .id(event.id)
                                                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            }
                        } header: {
                            yearFilterHeader
                        }
                    }
                    .padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(EventArchiveStyle.background)
        .navigationTitle("event.list.title")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(EventArchiveStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
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
                onPhotobooks: { onSelectTab(.photobooks) },
                onDiagnostics: { onSelectTab(.diagnostics) }
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
        .onAppear {
            // Home can unlove an Event while this list remains alive beneath its navigation push.
            Task { await loadEvents() }
        }
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
                    HStack(spacing: 12) {
                        selectionIndicator(isSelected: selectedEventIDs.contains(event.id))
                        eventArchiveRow(event)
                    }
                }
            } else {
            ZStack(alignment: .topTrailing) {
                NavigationLink {
                    EventDetailView(
                        event: event, initialHeroImage: loadedCoverImages[event.id],
                        onEventDeleted: { deletedID in
                            await removeEventFromList(deletedID, scrollProxy: scrollProxy)
                        }
                    )
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

    private func toggleLove(for event: PhotoEvent) async {
        let isLoved = !event.isLoved
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            try await store.setEventLoved(eventID: event.id, isLoved: isLoved)
            guard let index = allEvents.firstIndex(where: { $0.id == event.id }) else { return }
            allEvents[index].isLoved = isLoved
            onEventUpdated(allEvents[index])
        } catch {
            actionError = "Không thể cập nhật sự kiện yêu thích. Vui lòng thử lại."
        }
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

    private var filteredEvents: [PhotoEvent] {
        allEvents
            .filter { event in
                Self.isVisibleInProductionList(event)
                    && (selectedYear == nil || Calendar.current.component(.year, from: event.startDate) == selectedYear)
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

    private var availableYears: [Int] {
        Array(Set(allEvents.map { Calendar.current.component(.year, from: $0.startDate) })).sorted(by: >)
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

    private var yearFilterHeader: some View {
        EventArchiveYearFilter(
            years: availableYears,
            selectedYear: $selectedYear,
            eventCount: filteredEvents.count
        )
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
            Text("event.list.empty.title")
                .font(.headline)
            Text("event.list.empty.message")
                .font(.subheadline)
                .foregroundStyle(EventArchiveStyle.mutedText)
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
                Task { await loadEvents() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func loadEvents() async {
        isLoading = true
        errorMessage = nil
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            allEvents = try await store.fetchEvents(sortedBy: .scoreDescending)
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
            await loadEvents()
            selectedEventIDs.removeAll()
        } catch {
            actionError = "Không thể xoá các sự kiện đã chọn. Vui lòng thử lại."
        }
    }

    /// Called by `EventDetailView` after its repository delete succeeds but before it pops. The
    /// card immediately below the deleted one becomes the return anchor (or the preceding card
    /// when deleting the last row), preserving the reader's place instead of recreating at top.
    private func removeEventFromList(_ deletedID: PhotoEvent.ID, scrollProxy: ScrollViewProxy) async {
        let visibleEvents = filteredEvents
        guard let deletedIndex = visibleEvents.firstIndex(where: { $0.id == deletedID }) else { return }
        let returnAnchor = visibleEvents.dropFirst(deletedIndex + 1).first?.id
            ?? visibleEvents.prefix(deletedIndex).last?.id

        withAnimation(.easeInOut(duration: 0.3)) {
            allEvents.removeAll { $0.id == deletedID }
            selectedEventIDs.removeAll { $0 == deletedID }
        }
        guard let returnAnchor else { return }

        await Task.yield()
        // Run exactly once, after the removed row has left the LazyVStack, so this does not
        // compete with layout updates and produces no scroll-to-top flash on the pop transition.
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo(returnAnchor, anchor: .top)
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

private enum EventArchiveStyle {
    static let background = Color(red: 14 / 255, green: 13 / 255, blue: 16 / 255)
    static let primaryText = Color(red: 246 / 255, green: 241 / 255, blue: 234 / 255)
    static let mutedText = primaryText.opacity(0.45)
    static let divider = Color.white.opacity(0.07)
    static let accent = Color(red: 225 / 255, green: 135 / 255, blue: 91 / 255)
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

private struct EventArchiveYearFilter: View {
    let years: [Int]
    @Binding var selectedYear: Int?
    let eventCount: Int

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 9) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(years, id: \.self) { year in
                            chip(title: String(year), isSelected: selectedYear == year) {
                                select(year, proxy: proxy)
                            }
                            .id(Optional(year))
                        }
                        chip(title: localizedString("album.year_filter.all", defaultValue: "All"), isSelected: selectedYear == nil) {
                            select(nil, proxy: proxy)
                        }
                        .id(Optional<Int>.none)
                    }
                    .padding(.horizontal, 24)
                }

                Text(eventCountLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(EventArchiveStyle.mutedText)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var eventCountLabel: String {
        if let selectedYear {
            return "\(eventCount) sự kiện trong năm \(selectedYear)"
        }
        return "\(eventCount) sự kiện"
    }

    private func select(_ year: Int?, proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.25)) {
            selectedYear = year
        }
        withAnimation(.snappy(duration: 0.3)) {
            proxy.scrollTo(year, anchor: .center)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? EventArchiveStyle.background : EventArchiveStyle.mutedText)
                .padding(.horizontal, 16)
                .frame(height: 31)
                .background(isSelected ? EventArchiveStyle.accent : Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
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
    private static let thumbnailPixelSize = CGSize(width: 120, height: 120)

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.09))
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.eventPlace?.displayName ?? event.primaryLocationLabel ?? event.titleSuggestion)
                    .font(.system(size: 14.5))
                    .foregroundStyle(EventArchiveStyle.primaryText)
                    .lineLimit(1)
                Text(metadata)
                    .font(.system(size: 12))
                    .foregroundStyle(EventArchiveStyle.mutedText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 34)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            EventArchiveStyle.divider.frame(height: 1)
        }
        .contentShape(Rectangle())
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
