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
                    LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if filteredEvents.isEmpty {
                                emptyFilteredState
                            } else {
                                ForEach(filteredEvents) { event in
                                    eventRow(event, scrollProxy: scrollProxy)
                                        .id(event.id)
                                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                                }
                            }
                        } header: {
                            yearFilterHeader
                        }
                    }
                    .padding()
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("event.list.title")
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
                        eventCard(event, showsLoveControl: false)
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
                    eventCard(event, showsLoveControl: false)
                }

                loveButton(for: event)
                    .padding(10)
            }
            }
        }
        .buttonStyle(.plain)
    }

    private func eventCard(_ event: PhotoEvent, showsLoveControl: Bool = true) -> some View {
        EventCardView(
            event: event,
            assetProvider: assetProvider,
            onCoverLoaded: { loadedCoverImages[event.id] = $0 },
            onLoveTapped: showsLoveControl ? {
                Task { await toggleLove(for: event) }
            } : nil,
            onPlaceRequested: { event in
                Task { await resolvePlace(for: event) }
            }
        )
        .frame(maxWidth: .infinity)
        .frame(height: EventCardView.cardHeight)
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
                (selectedYear == nil || Calendar.current.component(.year, from: event.startDate) == selectedYear)
                    && (selectedType == nil || event.eventType == selectedType)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    private var availableYears: [Int] {
        Array(Set(allEvents.map { Calendar.current.component(.year, from: $0.startDate) })).sorted(by: >)
    }

    private var yearFilterHeader: some View {
        YearFilterBar(years: availableYears, selectedYear: $selectedYear, placesAllLast: true)
            .padding(.vertical, 10)
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

#Preview {
    NavigationStack {
        EventListView()
    }
    .modelContainer(
        for: [MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self],
        inMemory: true
    )
}
