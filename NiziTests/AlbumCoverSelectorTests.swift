//
//  AlbumCoverSelectorTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// Exercises `DefaultAlbumCoverSelector` in isolation from `PhotoImportanceEvaluating` — every
/// fixture here sets `importance` explicitly, since the selector's whole job post-refactor is to
/// pick from *already-scored* photos, never to score them itself (§ 6.4). See
/// `PhotoImportanceEvaluatorTests` for the scoring logic itself.
struct AlbumCoverSelectorTests {
    private func photo(
        id: String,
        width: Int = 1600,
        height: Int = 1200,
        creationDate: Date? = nil,
        importance: Double = 0,
        place: PhotoPlace? = nil
    ) -> AlbumPlanningPhoto {
        AlbumPlanningPhoto(
            id: id, eventId: "event-1", creationDate: creationDate, pixelWidth: width, pixelHeight: height,
            coordinate: nil, place: place, isFavorite: false, isEdited: false,
            burstIdentifier: nil, originalFilename: nil, exif: nil,
            importance: PhotoImportance(totalScore: importance, reasons: [])
        )
    }

    @Test func selectsHighestImportanceRegardlessOfResolution() throws {
        let selector = DefaultAlbumCoverSelector()
        let highImportanceSmall = photo(id: "important", width: 800, height: 600, importance: 60)
        let lowImportanceBig = photo(id: "big", width: 4000, height: 3000, importance: 10)
        let winner = try selector.selectCover(from: [highImportanceSmall, lowImportanceBig])
        #expect(winner.id == "important")
    }

    @Test func doesNotRecomputeScoring() throws {
        // A photo that would score very high under the *old* heuristic (favorite, huge, landscape)
        // must still lose to explicit importance if that's what's set — proving the selector
        // trusts `importance` rather than re-deriving its own score from favorite/resolution/orientation.
        let selector = DefaultAlbumCoverSelector()
        let wouldHaveWonUnderOldScoring = AlbumPlanningPhoto(
            id: "old-winner", eventId: "e", creationDate: nil, pixelWidth: 6000, pixelHeight: 4000,
            coordinate: nil, place: nil, isFavorite: true, isEdited: true,
            burstIdentifier: nil, originalFilename: nil, exif: nil,
            importance: PhotoImportance(totalScore: 1, reasons: [])
        )
        let explicitWinner = photo(id: "explicit-winner", width: 100, height: 100, importance: 99)
        let winner = try selector.selectCover(from: [wouldHaveWonUnderOldScoring, explicitWinner])
        #expect(winner.id == "explicit-winner")
    }

    @Test func tieBreaksByResolutionThenDateThenID() throws {
        let selector = DefaultAlbumCoverSelector()
        let earlyDate = Date(timeIntervalSince1970: 0)
        let laterDate = Date(timeIntervalSince1970: 1000)

        // Same importance — resolution decides.
        let smaller = photo(id: "smaller", width: 800, height: 600, importance: 50)
        let larger = photo(id: "larger", width: 4000, height: 3000, importance: 50)
        #expect(try selector.selectCover(from: [smaller, larger]).id == "larger")

        // Same importance and resolution — earlier date decides.
        let early = photo(id: "early", width: 800, height: 600, creationDate: earlyDate, importance: 50)
        let later = photo(id: "later", width: 800, height: 600, creationDate: laterDate, importance: 50)
        #expect(try selector.selectCover(from: [early, later]).id == "early")

        // Same importance, resolution, and date — lexical ID decides.
        let a = photo(id: "a-photo", width: 800, height: 600, importance: 50)
        let b = photo(id: "b-photo", width: 800, height: 600, importance: 50)
        #expect(try selector.selectCover(from: [b, a]).id == "a-photo")
    }

    @Test func emptyPhotoListThrows() {
        let selector = DefaultAlbumCoverSelector()
        #expect(throws: AlbumPlanningError.coverSelectionFailed) {
            try selector.selectCover(from: [])
        }
    }

    @Test func placeDoesNotAffectTieBreakBeyondImportance() throws {
        // Two photos tie on importance/resolution/date; one has a resolved place, the other
        // doesn't. Only the defined tie-break chain (resolution → date → ID) may decide — place
        // itself isn't a tie-break criterion, so lexical ID still wins here.
        let selector = DefaultAlbumCoverSelector()
        let withPlace = photo(id: "b-with-place", width: 800, height: 600, importance: 50, place: nil)
        let withoutPlace = photo(id: "a-no-place", width: 800, height: 600, importance: 50, place: nil)
        #expect(try selector.selectCover(from: [withPlace, withoutPlace]).id == "a-no-place")
    }
}
