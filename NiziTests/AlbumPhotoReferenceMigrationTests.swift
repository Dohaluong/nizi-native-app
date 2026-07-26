//
//  AlbumPhotoReferenceMigrationTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// docs/specs/SPEC-REAL-ALBUM.md § 36.1
struct AlbumPhotoReferenceMigrationTests {
    @Test func referenceEncodesAndDecodes() throws {
        let reference = AlbumPhotoReference(id: "asset-1", source: .applePhotos, sourceIdentifier: "asset-1", originalFilename: "IMG_0001.HEIC")
        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(AlbumPhotoReference.self, from: data)
        #expect(decoded == reference)
    }

    @Test func cropEncodesAndDecodes() throws {
        let crop = AlbumPhotoCrop(normalizedOffsetX: 0.2, normalizedOffsetY: -0.1, scale: 1.3)
        let data = try JSONEncoder().encode(crop)
        let decoded = try JSONDecoder().decode(AlbumPhotoCrop.self, from: data)
        #expect(decoded == crop)
    }

    @Test func assignmentEncodesInNewShape() throws {
        let assignment = AlbumPhotoAssignment(
            id: "a1", slotId: "photo-1",
            photo: AlbumPhotoReference(id: "asset-1", source: .applePhotos, sourceIdentifier: "asset-1", originalFilename: nil)
        )
        let data = try JSONEncoder().encode(assignment)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"photo\""))
        #expect(!json.contains("\"photoId\"")) // § 5.3 — never duplicates the ID under both keys
    }

    @Test func assignmentDecodesFromNewShape() throws {
        let json = """
        {"id":"a1","slotId":"photo-1","photo":{"id":"asset-1","source":"applePhotos","sourceIdentifier":"asset-1","originalFilename":null},"crop":{"normalizedOffsetX":0,"normalizedOffsetY":0,"scale":1}}
        """
        let decoded = try JSONDecoder().decode(AlbumPhotoAssignment.self, from: Data(json.utf8))
        #expect(decoded.photo.sourceIdentifier == "asset-1")
        #expect(decoded.photoId == "asset-1")
    }

    @Test func assignmentDecodesFromLegacyPhotoIdShape() throws {
        // § 6 — the exact shape every Draft persisted before this migration used.
        let legacyJSON = """
        {"id":"a1","slotId":"photo-1","photoId":"asset-legacy-1"}
        """
        let decoded = try JSONDecoder().decode(AlbumPhotoAssignment.self, from: Data(legacyJSON.utf8))
        #expect(decoded.photoId == "asset-legacy-1")
        #expect(decoded.photo.source == .applePhotos)
        #expect(decoded.photo.sourceIdentifier == "asset-legacy-1")
        #expect(decoded.crop == .centered)
    }

    @Test func sourceIdentifierIsNeverEmptyForLegacyInit() {
        let assignment = AlbumPhotoAssignment(id: "a1", slotId: "photo-1", photoId: "asset-1")
        #expect(!assignment.photo.sourceIdentifier.isEmpty)
    }

    @Test func computedPhotoIdMatchesReferenceId() {
        let assignment = AlbumPhotoAssignment(
            id: "a1", slotId: "photo-1",
            photo: AlbumPhotoReference(id: "internal-id", source: .applePhotos, sourceIdentifier: "asset-1", originalFilename: nil)
        )
        #expect(assignment.photoId == "internal-id")
    }
}
