//
//  PhotoEventRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

enum PhotoEventSortOrder {
    case scoreDescending
    case newestFirst
}

protocol PhotoEventRepository {
    /// Deletes every event still in a "not yet committed" status (new/viewed/dismissed/
    /// snoozed/merged) and inserts the freshly computed ones. Events already `.accepted`
    /// or `.convertedToAlbum` are left untouched — this is the MVP idempotency strategy that
    /// satisfies "rebuild never creates unbounded duplicates" without needing to diff shifting
    /// cluster boundaries across incremental scans. See docs/sprint/SPRINT-004-INTEGRATION-CHECKLIST.md.
    func replaceRebuildableEvents(_ events: [PhotoEvent]) async throws
    func fetchEvents(sortedBy order: PhotoEventSortOrder) async throws -> [PhotoEvent]
    /// Batched lookup by ID — mirrors `PhotoSessionRepository.fetchSessions(ids:)`. Lets Trips UI
    /// resolve a `PhotoTrip.eventIDs` list into real `PhotoEvent`s (for cover/photo/event counts)
    /// with one call across many trips, instead of a fetch-all-then-filter per trip.
    func fetchEvents(ids: [UUID]) async throws -> [PhotoEvent]
    /// Events surfaced on Home's "Kỷ niệm" section — user-loved OR Nizi-selected Auto Memories
    /// (SPRINT-NEXT § 18), sorted newest first.
    func fetchMemoryEvents() async throws -> [PhotoEvent]
    func setEventLoved(eventID: UUID, isLoved: Bool) async throws
    func setEventPlace(eventID: UUID, place: EventPlace?, state: EventPlaceResolutionState) async throws
    /// Removes only the local Event candidate and its derived curation data. It never calls the
    /// Photos framework or deletes any underlying library asset.
    func deleteEvent(id: UUID) async throws
    /// Merges `sourceID` into the selected destination Event. The destination keeps its identity
    /// and presentation metadata while its dates, sessions and assets are expanded to include the
    /// source; stale derived curation results for both Events are discarded.
    func mergeEvent(sourceID: UUID, into destinationID: UUID) async throws
}
