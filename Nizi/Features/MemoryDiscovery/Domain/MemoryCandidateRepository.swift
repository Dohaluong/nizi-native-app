//
//  MemoryCandidateRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// One `MemoryCandidate` row is normally all this ever holds (see docs/sprint/
/// SPRINT-FIRST-MEMORY-EXPERIENCE.md § 20) — `save` upserts in place rather than replacing a
/// whole collection, unlike `PhotoEventRepository.replaceRebuildableEvents`.
protocol MemoryCandidateRepository {
    func save(_ candidate: MemoryCandidate) async throws
    func fetchLatest() async throws -> MemoryCandidate?
    func updateSelection(id: UUID, selectedAssetIDs: [String]) async throws
}
