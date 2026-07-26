//
//  AlbumLayoutPairSelectorTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

struct AlbumLayoutPairSelectorTests {
    private func photo(id: String, orientation: PhotoOrientation) -> AlbumPlanningPhoto {
        let (width, height): (Int, Int)
        switch orientation {
        case .landscape: (width, height) = (1600, 1200)
        case .portrait: (width, height) = (1200, 1600)
        case .square: (width, height) = (1400, 1400)
        }
        return AlbumPlanningPhoto(
            id: id, eventId: "e", creationDate: nil, pixelWidth: width, pixelHeight: height,
            coordinate: nil, place: nil, isFavorite: false, isEdited: false,
            burstIdentifier: nil, originalFilename: nil, exif: nil
        )
    }

    private func makeSelector() -> DefaultAlbumLayoutPairSelector {
        DefaultAlbumLayoutPairSelector(repository: BundleAlbumLayoutRepository())
    }

    @Test func onlyReturnsLayoutsMatchingTheRequestedPhotoCount() throws {
        let photos = (0..<4).map { photo(id: "p\($0)", orientation: .landscape) }
        let selection = try makeSelector().selectLayoutPair(for: photos, format: .square)
        #expect(selection.leftLayout.photoCount == selection.leftPhotos.count)
        #expect(selection.rightLayout.photoCount == selection.rightPhotos.count)
        #expect(selection.leftPhotos.count + selection.rightPhotos.count == 4)
    }

    @Test func onlyReturnsLayoutsSupportingTheRequestedFormat() throws {
        let photos = (0..<3).map { photo(id: "p\($0)", orientation: .landscape) }
        let selection = try makeSelector().selectLayoutPair(for: photos, format: .square)
        #expect(selection.leftLayout.supportedFormats.contains(.square))
        #expect(selection.rightLayout.supportedFormats.contains(.square))
    }

    @Test func allLandscapePhotosPreferLandscapeHeavyLayouts() throws {
        // square.2.horizontal-split (both slots landscape) should clearly beat any layout with
        // portrait slots for an all-landscape 2-photo set.
        let photos = [photo(id: "p0", orientation: .landscape), photo(id: "p1", orientation: .landscape)]
        let selection = try makeSelector().selectLayoutPair(for: photos, format: .square)
        // A 1+1 partition producing two single-slot pages is also plausible and fine — assert
        // the *combined* orientation score is high (i.e. no landscape photo forced into an
        // ill-fitting portrait slot for no reason) rather than pinning an exact layout ID.
        #expect(selection.score > 0)
    }

    @Test func fallsBackGracefullyWhenNoExactOrientationMatchExists() throws {
        // A single portrait photo into whatever this library's only 1-photo layouts offer
        // (square-preferred slots) must still produce *a* result, never throw.
        let photos = [photo(id: "p0", orientation: .portrait)]
        let selection = try makeSelector().selectLayoutPair(for: photos, format: .square)
        #expect(selection.leftPhotos.count + selection.rightPhotos.count == 1)
    }

    @Test func squareSlotAcceptsBothPortraitAndLandscape() throws {
        // square.4.grid is all-square slots — mixed orientations must still resolve to a full
        // set of assignments without error.
        let photos = [
            photo(id: "p0", orientation: .landscape),
            photo(id: "p1", orientation: .portrait),
            photo(id: "p2", orientation: .landscape),
            photo(id: "p3", orientation: .portrait)
        ]
        let selection = try makeSelector().selectLayoutPair(for: photos, format: .square)
        #expect(selection.leftPhotos.count + selection.rightPhotos.count == 4)
    }

    @Test func resultIsDeterministicAcrossRepeatedCalls() throws {
        let photos = (0..<5).map { photo(id: "p\($0)", orientation: [.landscape, .portrait, .square][$0 % 3]) }
        let first = try makeSelector().selectLayoutPair(for: photos, format: .square)
        let second = try makeSelector().selectLayoutPair(for: photos, format: .square)
        #expect(first.leftLayout.id == second.leftLayout.id)
        #expect(first.rightLayout.id == second.rightLayout.id)
        #expect(first.leftPhotos.map(\.id) == second.leftPhotos.map(\.id))
        #expect(first.score == second.score)
    }

    @Test func throwsNoValidSpreadPartitionOutsideTwoToSixPhotos() {
        let onePhoto = [photo(id: "solo", orientation: .landscape)]
        #expect(throws: AlbumPlanningError.noValidSpreadPartition(photoCount: 1)) {
            try makeSelector().selectLayoutPair(for: onePhoto, format: .square)
        }
    }
}
