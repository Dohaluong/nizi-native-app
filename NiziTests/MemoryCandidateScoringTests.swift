//
//  MemoryCandidateScoringTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import Testing
@testable import Nizi

struct MemoryCandidateScoringTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!

    private func makeEvent(
        score: Double,
        assetCount: Int = 10,
        primaryLocationLabel: String? = nil,
        discoveryReasons: [DiscoveryReason] = []
    ) -> PhotoEvent {
        PhotoEvent(
            id: UUID(),
            titleSuggestion: "Trip",
            startDate: Self.reference,
            endDate: Self.reference.addingTimeInterval(86400),
            primaryLocationLabel: primaryLocationLabel,
            eventType: .trip,
            score: score,
            status: .new,
            sessionIDs: [UUID()],
            assetIDs: (0..<assetCount).map { "asset-\($0)" },
            coverAssetID: "asset-0",
            discoveryReasons: discoveryReasons,
            algorithmVersion: 1,
            createdAt: Self.reference,
            updatedAt: Self.reference
        )
    }

    @Test func baseScoreScalesEventScoreTo100() {
        let event = makeEvent(score: 0.5, assetCount: 5)
        let score = DefaultMemoryCandidateScoring().score(event: event)
        #expect(score == 50)
    }

    @Test func bonusesStackForLocationLargeEventAndFavorites() {
        let favoriteReason = DiscoveryReason(kind: .favoritesPresent, text: "has favorites")
        let event = makeEvent(score: 0.5, assetCount: 25, primaryLocationLabel: "Da Nang", discoveryReasons: [favoriteReason])
        let score = DefaultMemoryCandidateScoring().score(event: event)
        #expect(score == 65) // 50 base + 5 location + 5 large event + 5 favorites
    }

    @Test func scoreClampsAt100() {
        let favoriteReason = DiscoveryReason(kind: .favoritesPresent, text: "has favorites")
        let event = makeEvent(score: 1.0, assetCount: 25, primaryLocationLabel: "Da Nang", discoveryReasons: [favoriteReason])
        let score = DefaultMemoryCandidateScoring().score(event: event)
        #expect(score == 100)
    }
}

struct MemoryBuilderTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!

    private func makeEvent(assetIDs: [String] = ["asset-1", "asset-2", "asset-3"], coverAssetID: String? = "cover-asset") -> PhotoEvent {
        PhotoEvent(
            id: UUID(),
            titleSuggestion: "Trip",
            startDate: Self.reference,
            endDate: Self.reference.addingTimeInterval(86400),
            primaryLocationLabel: "Da Nang",
            eventType: .trip,
            score: 0.8,
            status: .new,
            sessionIDs: [UUID()],
            assetIDs: assetIDs,
            coverAssetID: coverAssetID,
            discoveryReasons: [],
            algorithmVersion: 1,
            createdAt: Self.reference,
            updatedAt: Self.reference
        )
    }

    private func makeItem(assetID: String, isSelected: Bool, qualityScore: Int, sortOrder: Int) -> PhotoCurationItem {
        PhotoCurationItem(
            id: UUID(),
            assetID: assetID,
            sortOrder: sortOrder,
            qualityScore: qualityScore,
            similarityClusterID: "cluster-\(assetID)",
            isSuggested: true,
            isSelected: isSelected,
            selectionSource: .systemSuggested
        )
    }

    private func makeCuration(event: PhotoEvent, items: [PhotoCurationItem]) -> EventCurationResult {
        let group = PhotoCurationGroup(
            id: UUID(), sessionID: nil, startDate: Self.reference, endDate: Self.reference, sortOrder: 0, items: items
        )
        return EventCurationResult(
            photoEventID: event.id, status: .completed, algorithmVersion: 1,
            createdAt: Self.reference, updatedAt: Self.reference, completedAt: Self.reference,
            sourceAssetCount: items.count, errorMessage: nil, groups: [group]
        )
    }

    @Test func buildReturnsNilWhenNothingSelected() {
        let event = makeEvent()
        let curation = makeCuration(event: event, items: [
            makeItem(assetID: "asset-1", isSelected: false, qualityScore: 80, sortOrder: 0)
        ])
        let memory = MemoryBuilder().build(event: event, curation: curation, score: 80)
        #expect(memory == nil)
    }

    @Test func buildPicksHighestQualityScoreSelectedItemAsCover() throws {
        let event = makeEvent()
        let curation = makeCuration(event: event, items: [
            makeItem(assetID: "asset-1", isSelected: true, qualityScore: 60, sortOrder: 0),
            makeItem(assetID: "asset-2", isSelected: true, qualityScore: 90, sortOrder: 1),
            makeItem(assetID: "asset-3", isSelected: false, qualityScore: 99, sortOrder: 2)
        ])
        let memory = try #require(MemoryBuilder().build(event: event, curation: curation, score: 80))
        #expect(memory.coverAssetID == "asset-2")
        #expect(memory.selectedAssetIDs == ["asset-1", "asset-2"])
        #expect(memory.status == .ready)
        #expect(memory.totalPhotoCount == 2)
    }

    @Test func buildFallbackCapsAtTwelvePhotosAndUsesEventCover() throws {
        let event = makeEvent(assetIDs: (0..<20).map { "asset-\($0)" }, coverAssetID: "asset-5")
        let memory = try #require(MemoryBuilder().buildFallback(event: event))
        #expect(memory.selectedAssetIDs.count == 12)
        #expect(memory.coverAssetID == "asset-5")
        #expect(memory.status == .ready)
    }

    @Test func buildFallbackReturnsNilForEmptyEvent() {
        let event = makeEvent(assetIDs: [], coverAssetID: nil)
        #expect(MemoryBuilder().buildFallback(event: event) == nil)
    }
}
