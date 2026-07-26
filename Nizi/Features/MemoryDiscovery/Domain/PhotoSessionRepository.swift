//
//  PhotoSessionRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

protocol PhotoSessionRepository {
    /// Replaces the whole session table with a freshly computed set. Sessions carry no
    /// user-facing status of their own (only candidates do), so unlike candidates there's
    /// nothing to preserve across a rebuild.
    func replaceRebuildableSessions(_ sessions: [PhotoSession]) async throws
    func fetchSessions(ids: [UUID]) async throws -> [PhotoSession]
}
