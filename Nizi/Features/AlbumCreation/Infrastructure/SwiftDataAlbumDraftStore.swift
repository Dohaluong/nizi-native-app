//
//  SwiftDataAlbumDraftStore.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import SwiftData

/// Background-safe SwiftData repository for `AlbumDraft`s — same `@ModelActor` pattern as
/// `SwiftDataMemoryDiscoveryStore`, kept as its own store (not folded into that actor) since
/// Album Creation is a separate module (see docs/architecture/ARCHITECTURE.md § 2: modules don't
/// reach into each other's infrastructure).
@ModelActor
actor SwiftDataAlbumDraftStore: AlbumDraftRepository {
    func save(_ draft: AlbumDraft) async throws {
        let draftID = draft.id
        var descriptor = FetchDescriptor<MDAlbumDraft>(predicate: #Predicate { $0.draftID == draftID })
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            try existing.apply(draft)
        } else {
            modelContext.insert(try MDAlbumDraft(draft: draft))
        }
        try modelContext.save()
    }

    /// § 27.3 — always updates the existing row (never inserts a new one for an edit); preserves
    /// `createdAt`, and the caller is expected to have already set a fresh `updatedAt` on `draft`.
    func updateDraft(_ draft: AlbumDraft) async throws {
        let draftID = draft.id
        var descriptor = FetchDescriptor<MDAlbumDraft>(predicate: #Predicate { $0.draftID == draftID })
        descriptor.fetchLimit = 1

        guard let existing = try modelContext.fetch(descriptor).first else {
            // No prior row to update — fall back to inserting, since there's nothing to
            // preserve `createdAt` from anyway.
            modelContext.insert(try MDAlbumDraft(draft: draft))
            try modelContext.save()
            return
        }
        try existing.apply(draft)
        try modelContext.save()
    }

    func fetchDraft(id: String) async throws -> AlbumDraft? {
        var descriptor = FetchDescriptor<MDAlbumDraft>(predicate: #Predicate { $0.draftID == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { try $0.decodedDraft() }
    }

    func fetchAllDrafts() async throws -> [AlbumDraft] {
        let descriptor = FetchDescriptor<MDAlbumDraft>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map { try $0.decodedDraft() }
    }

    func deleteDraft(id: String) async throws {
        var descriptor = FetchDescriptor<MDAlbumDraft>(predicate: #Predicate { $0.draftID == id })
        descriptor.fetchLimit = 1
        guard let existing = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }
}
