//
//  AlbumPrimaryPlaceResolverTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

struct AlbumPrimaryPlaceResolverTests {
    private func place(_ name: String) -> PhotoPlace {
        PhotoPlace(
            coordinate: PhotoCoordinate(latitude: 0, longitude: 0)!, name: name, subLocality: nil,
            locality: nil, subAdministrativeArea: nil, administrativeArea: nil, country: nil,
            isoCountryCode: nil, displayName: name
        )
    }

    private func photo(id: String, place: PhotoPlace?, importance: Double = 0) -> AlbumPlanningPhoto {
        AlbumPlanningPhoto(
            id: id, eventId: "e", creationDate: nil, pixelWidth: 1600, pixelHeight: 1200,
            coordinate: nil, place: place, isFavorite: false, isEdited: false,
            burstIdentifier: nil, originalFilename: nil, exif: nil,
            importance: PhotoImportance(totalScore: importance, reasons: [])
        )
    }

    @Test func picksTheMostFrequentPlace() {
        let photos = [
            photo(id: "1", place: place("Sydney")), photo(id: "2", place: place("Sydney")),
            photo(id: "3", place: place("Melbourne"))
        ]
        #expect(AlbumPrimaryPlaceResolver.resolve(photos: photos, heroPhotoId: nil)?.displayName == "Sydney")
    }

    @Test func tieBreaksByHeroPhoto() {
        let photos = [
            photo(id: "1", place: place("Sydney")),
            photo(id: "2", place: place("Melbourne"))
        ]
        #expect(AlbumPrimaryPlaceResolver.resolve(photos: photos, heroPhotoId: "2")?.displayName == "Melbourne")
    }

    @Test func albumScopePrefersMajorityOverCoverPlace() {
        let photos = [
            photo(id: "cover", place: place("Melbourne")),
            photo(id: "2", place: place("Sydney")),
            photo(id: "3", place: place("Sydney"))
        ]
        let result = AlbumPrimaryPlaceResolver.resolveAlbumPlace(photos: photos, coverPhotoId: "cover", mainEventPlace: nil)
        #expect(result?.displayName == "Sydney")
    }

    @Test func albumScopeFallsBackToCoverPlaceWhenNoMajority() {
        let photos = [photo(id: "cover", place: place("Melbourne"))]
        let result = AlbumPrimaryPlaceResolver.resolveAlbumPlace(photos: photos, coverPhotoId: "cover", mainEventPlace: nil)
        #expect(result?.displayName == "Melbourne")
    }

    @Test func noPlaceAnywhereReturnsNil() {
        let photos = [photo(id: "1", place: nil), photo(id: "2", place: nil)]
        #expect(AlbumPrimaryPlaceResolver.resolve(photos: photos, heroPhotoId: nil) == nil)
        #expect(AlbumPrimaryPlaceResolver.resolveAlbumPlace(photos: photos, coverPhotoId: "1", mainEventPlace: nil) == nil)
    }
}
