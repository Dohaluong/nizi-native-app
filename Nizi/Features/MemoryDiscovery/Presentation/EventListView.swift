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
    @State private var selectedYear: Int?
    @State private var selectedType: EventType?
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Tracked automatically by `.scrollPosition(id:)` as the user scrolls, and re-applied by the
    /// same modifier whenever this view lays out again — so returning from a pushed
    /// `EventDetailView` lands back where the user left off instead of snapping to the top
    /// (plain `ScrollView` doesn't reliably preserve offset across a NavigationStack push/pop).
    @State private var scrolledEventID: PhotoEvent.ID?
    /// The exact `UIImage` each `EventCardView` is currently displaying, reported back as
    /// soon as it loads — see the Hero-image follow-up. Read (not re-fetched) when a card is
    /// tapped, so `EventDetailView` never opens with a blank cover for an event whose card
    /// visibly already had one. Not a `NavigationPath`/Hashable concern here: this list still uses
    /// the inline `NavigationLink { destination } label: { }` form, so the destination closure can
    /// just read this directly — nothing needs to go through path-based navigation.
    @State private var loadedCoverImages: [PhotoEvent.ID: PlatformImage] = [:]

    private let assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if filteredEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredEvents) { event in
                            eventRow(event)
                        }
                    }
                    .padding()
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrolledEventID)
            }
        }
        .navigationTitle("event.list.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }
        }
        .task { await loadEvents() }
    }

    // Pulled out of `body` — inlined, this pushed the surrounding `ScrollView`/`LazyVStack`/
    // `ForEach` expression past what the type checker could resolve in reasonable time ("unable
    // to type-check this expression in reasonable time"), a known SwiftUI failure mode once a
    // `body` accumulates enough nested closures/generics. Splitting into a helper with an
    // explicit return type gives the compiler a much smaller expression to solve at a time.
    @ViewBuilder
    private func eventRow(_ event: PhotoEvent) -> some View {
        // The iOS 18 `.zoom` navigation transition (Hero-style zoom from this card's cover into
        // the detail screen) was tried and reverted — it was inconsistent card to card even after
        // the underlying card-layout bugs were fixed, which points to a framework reliability
        // limit for this scenario rather than something fixable from this view. A plain push is
        // reliable every time, which matters more than the zoom flourish.
        //
        // The destination closure reads `loadedCoverImages` live, at the moment the user actually
        // taps — not a stale snapshot taken when this NavigationLink was constructed — so if the
        // card has already loaded its cover by then, the detail screen opens with it immediately.
        NavigationLink {
            EventDetailView(event: event, initialHeroImage: loadedCoverImages[event.id])
        } label: {
            // `NavigationLink` (with `.buttonStyle(.plain)`) sizes itself off the label's *ideal*
            // size, and `EventCardView`'s label root is a `GeometryReader` — a `GeometryReader`
            // asked for its ideal/unconstrained size (which is exactly what an ideal-size probe
            // does) has no natural answer, so that probe is where per-row inconsistency could
            // actually be coming from despite every row being constructed identically. Forcing an
            // explicit, unambiguous width/height right here — on every row, before `NavigationLink`
            // ever gets to ask — removes that ambiguity instead of leaving it up to how the probe
            // happens to resolve for a given row.
            EventCardView(
                event: event,
                assetProvider: assetProvider,
                onCoverLoaded: { loadedCoverImages[event.id] = $0 }
            )
            .frame(maxWidth: .infinity)
            .frame(height: EventCardView.cardHeight)
        }
        .buttonStyle(.plain)
    }

    private var filteredEvents: [PhotoEvent] {
        allEvents.filter { event in
            (selectedYear == nil || Calendar.current.component(.year, from: event.startDate) == selectedYear)
                && (selectedType == nil || event.eventType == selectedType)
        }
    }

    private var availableYears: [Int] {
        Array(Set(allEvents.map { Calendar.current.component(.year, from: $0.startDate) })).sorted(by: >)
    }

    private var filterMenu: some View {
        Menu {
            Picker("event.list.filter.year_field", selection: $selectedYear) {
                Text("event.list.filter.all_years").tag(Int?.none)
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(Int?.some(year))
                }
            }
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
        } catch {
            errorMessage = localizedString("event.list.error.load_failed", defaultValue: "Couldn't load the events list.")
        }
        isLoading = false
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
