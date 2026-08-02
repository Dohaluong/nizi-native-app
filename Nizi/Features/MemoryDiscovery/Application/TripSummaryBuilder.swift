//
//  TripSummaryBuilder.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

/// A read-only, display-ready projection of a `PhotoTrip` — its own fields plus counts/cover
/// derived by resolving `eventIDs` into real `PhotoEvent`s. Never persisted; rebuilt on every
/// screen load from already-persisted Trip + Event data. No Discovery, no geocoding.
struct TripSummary: Identifiable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    /// A `var`, not `let` — callers that lazily resolve a place after this summary was built
    /// (`HomeView`/`TripsListView`, mirroring `TripDetailView`'s own resolve) mutate this in place
    /// instead of forcing a full store refetch just to reflect one trip's new name.
    var primaryPlaceName: String?
    let classification: TravelClassification
    let eventCount: Int
    let photoCount: Int
    let coverAssetID: String?
    /// The trip's constituent Events, in the trip's own declared order — lets `TripDetailView`
    /// independently resolve the trip's full photo list via `PhotoEventRepository.fetchEvents(ids:)`.
    var eventIDs: [UUID] = []
    /// The trip's representative coordinate (farthest point from home) — lets `TripDetailView`
    /// lazily re-resolve a place name on open when `primaryPlaceName` is still missing/empty,
    /// mirroring `EventPlaceEnrichmentService`'s lazy per-item resolution for Events.
    var primaryLatitude: Double? = nil
    var primaryLongitude: Double? = nil
}

extension TripSummary {
    /// `PhotoPlaceDisplayNameBuilder.makeDisplayName` can legitimately return `""` (not `nil`)
    /// when a resolved placemark has no usable fields at all — its own doc comment calls this
    /// out explicitly as "a legitimate domain value; the UI layer decides how to present that."
    /// Every Trips UI screen wants the same presentation decision (fall back to the
    /// classification label), so it lives here once instead of every screen's own `??` missing
    /// the empty-string case and rendering a blank title.
    var displayPlaceName: String? {
        guard let primaryPlaceName, !primaryPlaceName.isEmpty else { return nil }
        return primaryPlaceName
    }

    /// Same inclusive day-count formula as `EventCardView.durationDays` /
    /// `TripDiscoveryDiagnosticsView.dayCount` — kept here so every Trips UI screen reuses one
    /// source instead of recomputing it independently.
    var durationDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0) + 1
    }

    /// A compact `d-d/M/yyyy`-style range (e.g. "22-25/7/2026"), collapsing to just the shared
    /// parts when start/end share a month/year — one canonical source so Trip Detail's Hero, the
    /// Home rail, and the Trips list all render the exact same format.
    var dateRangeText: String {
        let calendar = Calendar.current
        let start = calendar.dateComponents([.day, .month, .year], from: startDate)
        let end = calendar.dateComponents([.day, .month, .year], from: endDate)
        guard let startDay = start.day, let startMonth = start.month, let startYear = start.year,
              let endDay = end.day, let endMonth = end.month, let endYear = end.year else {
            return startDate.formatted(.dateTime.day().month().year())
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

    init(trip: PhotoTrip, events: [PhotoEvent]) {
        id = trip.id
        startDate = trip.startDate
        endDate = trip.endDate
        primaryPlaceName = trip.primaryPlaceName
        classification = trip.classification
        eventCount = events.count
        photoCount = events.reduce(0) { $0 + $1.assetCount }
        // First event, in the trip's own declared `eventIDs` order, that actually has a cover —
        // a Trip has no cover photo of its own.
        let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        coverAssetID = trip.eventIDs
            .compactMap { eventsByID[$0] }
            .compactMap(\.coverAssetID)
            .first
        eventIDs = trip.eventIDs
        primaryLatitude = trip.primaryLatitude
        primaryLongitude = trip.primaryLongitude
    }
}

/// Batches every Trip's Event resolution into exactly one `fetchEvents(ids:)` call, so this stays
/// cheap regardless of how many trips are being summarized. Read-only; never mutates persisted
/// state, never re-runs Trip/Event Discovery.
enum TripSummaryBuilder {
    static func makeSummaries(
        trips: [PhotoTrip],
        eventRepository: PhotoEventRepository
    ) async throws -> [TripSummary] {
        let allEventIDs = Array(Set(trips.flatMap(\.eventIDs)))
        let eventsByID: [UUID: PhotoEvent]
        if allEventIDs.isEmpty {
            eventsByID = [:]
        } else {
            let events = try await eventRepository.fetchEvents(ids: allEventIDs)
            eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        }
        // `trips.map` preserves the caller's original order (already newest-first from
        // `fetchTrips()`) — no re-sort needed here.
        return trips.map { trip in
            let tripEvents = trip.eventIDs.compactMap { eventsByID[$0] }
            return TripSummary(trip: trip, events: tripEvents)
        }
    }
}
