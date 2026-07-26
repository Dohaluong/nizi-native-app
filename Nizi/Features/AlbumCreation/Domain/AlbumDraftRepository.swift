//
//  AlbumDraftRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

protocol AlbumDraftRepository {
    func save(_ draft: AlbumDraft) async throws
    /// Updates an existing row in place — preserves `draftId`/`createdAt`, sets `updatedAt`.
    /// Never creates a new row for an edit (docs/specs/SPEC-REAL-ALBUM.md § 27.3).
    func updateDraft(_ draft: AlbumDraft) async throws
    func fetchDraft(id: String) async throws -> AlbumDraft?
    func fetchAllDrafts() async throws -> [AlbumDraft]
    /// Deletes the persisted Draft row only — never touches the Photos Library (no
    /// `PHAssetChangeRequest` anywhere in this app's edit/delete paths).
    func deleteDraft(id: String) async throws
}
