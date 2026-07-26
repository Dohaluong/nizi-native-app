//
//  SwiftDataCollectionStyleRepositoryTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData
import Testing
@testable import Nizi

struct SwiftDataCollectionStyleRepositoryTests {
    private func makeRepository() throws -> SwiftDataCollectionStyleRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MDCollectionEditStyle.self, configurations: configuration)
        return SwiftDataCollectionStyleRepository(modelContainer: container)
    }

    private func makeStyle(
        type: CollectionType = .album,
        id: String = "album-1",
        createdAt: Date = Date(timeIntervalSince1970: 1000)
    ) -> CollectionEditStyle {
        CollectionEditStyle(
            collectionType: type, collectionId: id, presetId: "warm-memory", presetIntensity: 0.65,
            autoEnhanceEachPhoto: false, createdAt: createdAt, updatedAt: createdAt
        )
    }

    @Test
    func getStyleReturnsNilWhenNeverSaved() async throws {
        let repository = try makeRepository()
        let style = try await repository.getStyle(type: .album, id: "album-1")
        #expect(style == nil)
    }

    @Test
    func savingPersistsIt() async throws {
        let repository = try makeRepository()
        try await repository.saveStyle(makeStyle())

        let loaded = try await repository.getStyle(type: .album, id: "album-1")
        #expect(loaded?.presetId == "warm-memory")
        #expect(loaded?.presetIntensity == 0.65)
    }

    @Test
    func albumAndEventWithTheSameIdAreIndependent() async throws {
        let repository = try makeRepository()
        var albumStyle = makeStyle(type: .album, id: "shared-id")
        albumStyle.presetId = "warm-memory"
        var eventStyle = makeStyle(type: .event, id: "shared-id")
        eventStyle.presetId = "night-street"

        try await repository.saveStyle(albumStyle)
        try await repository.saveStyle(eventStyle)

        let loadedAlbum = try await repository.getStyle(type: .album, id: "shared-id")
        let loadedEvent = try await repository.getStyle(type: .event, id: "shared-id")
        #expect(loadedAlbum?.presetId == "warm-memory")
        #expect(loadedEvent?.presetId == "night-street")
    }

    @Test
    func updateDoesNotCreateADuplicateRowAndPreservesCreatedAt() async throws {
        let repository = try makeRepository()
        let original = makeStyle(createdAt: Date(timeIntervalSince1970: 1000))
        try await repository.saveStyle(original)

        var edited = original
        edited.presetIntensity = 0.9
        edited.updatedAt = Date(timeIntervalSince1970: 5000)
        try await repository.saveStyle(edited)

        let loaded = try await repository.getStyle(type: .album, id: "album-1")
        #expect(loaded?.presetIntensity == 0.9)
        #expect(loaded?.createdAt == Date(timeIntervalSince1970: 1000))
        #expect(loaded?.updatedAt == Date(timeIntervalSince1970: 5000))
    }

    @Test
    func autoEnhanceEachPhotoRoundTrips() async throws {
        let repository = try makeRepository()
        var style = makeStyle()
        style.autoEnhanceEachPhoto = true
        try await repository.saveStyle(style)

        let loaded = try await repository.getStyle(type: .album, id: "album-1")
        #expect(loaded?.autoEnhanceEachPhoto == true)
    }
}
