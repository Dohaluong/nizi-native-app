//
//  EventCurationRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

protocol EventCurationRepository {
    func result(for photoEventID: UUID) async throws -> EventCurationResult?
    /// Replaces the whole result (groups + items) for this event. Only ever called when a
    /// fresh curation run completes — never touches a result the user has since edited, because
    /// a cache-valid result is read via `result(for:)` and never re-curated. See § 18/19.
    func saveResult(_ result: EventCurationResult) async throws
    /// The one path a user's tap takes — mutates a single item's selection in place,
    /// independent of any curation run.
    func updateItemSelection(itemID: UUID, isSelected: Bool, source: SelectionSource) async throws
    func markStatus(photoEventID: UUID, status: CurationStatus, errorMessage: String?) async throws
    func clearResult(for photoEventID: UUID) async throws
}
