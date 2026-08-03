//
//  EventListVisibilityFilterTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation
import Testing
@testable import Nizi

/// SPRINT-FAST-EVENT-QUALITY § 8: the production Event List hides `.hiddenNoise` by default;
/// Diagnostics (which reads the same repository unfiltered) still sees everything. This tests
/// only the pure predicate `EventListView.isVisibleInProductionList(_:)` — not the full `View`.
struct EventListVisibilityFilterTests {
    private func makeEvent(visibility: EventVisibility) -> PhotoEvent {
        let now = Date()
        return PhotoEvent(
            id: UUID(),
            titleSuggestion: "Test",
            startDate: now,
            endDate: now,
            primaryLocationLabel: nil,
            eventType: .dayEvent,
            score: 0.5,
            status: .new,
            sessionIDs: [UUID()],
            assetIDs: ["asset-1"],
            coverAssetID: "asset-1",
            discoveryReasons: [],
            algorithmVersion: 1,
            createdAt: now,
            updatedAt: now,
            eventVisibility: visibility
        )
    }

    @Test func normalAndLowValueAreVisible() {
        #expect(EventListView.isVisibleInProductionList(makeEvent(visibility: .normal)))
        #expect(EventListView.isVisibleInProductionList(makeEvent(visibility: .lowValue)))
    }

    @Test func hiddenNoiseIsNotVisible() {
        #expect(!EventListView.isVisibleInProductionList(makeEvent(visibility: .hiddenNoise)))
    }

    /// § user request — "Automemory chỉ có tác dụng lúc đầu": the Memory tab predicate reads
    /// `isLoved` only — `isAutoMemory` (which the evaluator recomputes on every rebuild,
    /// independent of any user decision) plays no ongoing part in it.
    @Test func isMemoryReadsOnlyIsLovedNotIsAutoMemory() {
        var loved = makeEvent(visibility: .normal)
        loved.isLoved = true
        #expect(EventListView.isMemory(loved))

        var autoMemoryButUnloved = makeEvent(visibility: .normal)
        autoMemoryButUnloved.isAutoMemory = true
        autoMemoryButUnloved.isLoved = false
        #expect(!EventListView.isMemory(autoMemoryButUnloved))

        let neither = makeEvent(visibility: .normal)
        #expect(!EventListView.isMemory(neither))
    }
}
