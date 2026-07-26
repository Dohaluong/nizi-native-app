//
//  SwiftDataAlbumDraftStoreTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import SwiftData
import Testing
@testable import Nizi

/// docs/specs/SPEC-REAL-ALBUM.md § 36.10
struct SwiftDataAlbumDraftStoreTests {
    private func makeStore() throws -> SwiftDataAlbumDraftStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MDAlbumDraft.self, configurations: configuration)
        return SwiftDataAlbumDraftStore(modelContainer: container)
    }

    private func makeDraft(id: String = "draft-1", createdAt: Date = Date(timeIntervalSince1970: 1000)) -> AlbumDraft {
        let reference = AlbumPhotoReference(id: "asset-1", source: .applePhotos, sourceIdentifier: "asset-1", originalFilename: nil)
        let page = AlbumDraftPage(
            id: "page-1", order: 0, layoutId: "square.1.inset", format: .square,
            assignments: [AlbumPhotoAssignment(id: "a1", slotId: "photo-1", photo: reference)],
            sourceEventIds: ["e1"]
        )
        let spread = AlbumDraftSpread(id: "spread-1", order: 0, sourceEventIds: ["e1"], leftPage: page, rightPage: page)
        return AlbumDraft(
            id: id, title: "Test Album", subtitle: nil, coverPhotoId: "asset-1",
            startDate: nil, endDate: nil, primaryLocationName: nil, primaryPlace: nil,
            sourceEvents: [], spreads: [spread], createdAt: createdAt, planningVersion: 1, planningLog: nil
        )
    }

    @Test func savingANewAlbumPersistsIt() async throws {
        let store = try makeStore()
        try await store.save(makeDraft())
        let loaded = try await store.fetchDraft(id: "draft-1")
        #expect(loaded?.title == "Test Album")
    }

    @Test func updateDraftPreservesCreatedAtAndChangesUpdatedAt() async throws {
        let store = try makeStore()
        let original = makeDraft(createdAt: Date(timeIntervalSince1970: 1000))
        try await store.save(original)

        var edited = original
        edited.title = "Renamed"
        edited.updatedAt = Date(timeIntervalSince1970: 5000)
        try await store.updateDraft(edited)

        let loaded = try await store.fetchDraft(id: "draft-1")
        #expect(loaded?.title == "Renamed")
        #expect(loaded?.createdAt == Date(timeIntervalSince1970: 1000))
        #expect(loaded?.updatedAt == Date(timeIntervalSince1970: 5000))
    }

    @Test func updateDoesNotCreateADuplicateRow() async throws {
        let store = try makeStore()
        try await store.save(makeDraft())
        var edited = makeDraft()
        edited.title = "Updated"
        try await store.updateDraft(edited)

        let all = try await store.fetchAllDrafts()
        #expect(all.count == 1)
    }

    @Test func photoReferenceRoundTripsThroughSwiftData() async throws {
        let store = try makeStore()
        try await store.save(makeDraft())
        let loaded = try await store.fetchDraft(id: "draft-1")
        #expect(loaded?.spreads.first?.leftPage.assignments.first?.photo.sourceIdentifier == "asset-1")
    }

    @Test func cropRoundTripsThroughSwiftData() async throws {
        let store = try makeStore()
        var draft = makeDraft()
        draft.spreads[0].leftPage.assignments[0].crop = AlbumPhotoCrop(normalizedOffsetX: 0.3, normalizedOffsetY: -0.2, scale: 1.5)
        try await store.save(draft)

        let loaded = try await store.fetchDraft(id: "draft-1")
        #expect(loaded?.spreads.first?.leftPage.assignments.first?.crop.scale == 1.5)
    }

    @Test func oldDraftJSONStillDecodesThroughTheStore() async throws {
        // Simulates a row persisted before AlbumPhotoReference/updatedAt/flat columns existed.
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MDAlbumDraft.self, configurations: configuration)
        let context = ModelContext(container)

        let legacyJSON = """
        {"id":"legacy-1","title":"Legacy Album","coverPhotoId":"asset-1","sourceEvents":[],
         "spreads":[{"id":"s1","order":0,"sourceEventIds":[],
           "leftPage":{"id":"p1","order":0,"layoutId":"square.1.inset","format":"square",
             "assignments":[{"id":"a1","slotId":"photo-1","photoId":"asset-1"}],"sourceEventIds":[]},
           "rightPage":{"id":"p2","order":1,"layoutId":"square.1.inset","format":"square",
             "assignments":[{"id":"a2","slotId":"photo-1","photoId":"asset-1"}],"sourceEventIds":[]}}],
         "createdAt":0}
        """
        let legacyModel = MDAlbumDraft.self
        _ = legacyModel // silence unused-import-style warnings if any
        let row = try MDAlbumDraft(draft: JSONDecoder().decode(AlbumDraft.self, from: Data(legacyJSON.utf8)))
        context.insert(row)
        try context.save()

        let store = SwiftDataAlbumDraftStore(modelContainer: container)
        let loaded = try await store.fetchDraft(id: "legacy-1")
        #expect(loaded?.title == "Legacy Album")
        #expect(loaded?.spreads.first?.leftPage.assignments.first?.photoId == "asset-1")
    }
}
