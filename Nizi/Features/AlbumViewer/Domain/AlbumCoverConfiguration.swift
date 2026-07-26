//
//  AlbumCoverConfiguration.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// What the book-style cover needs to render — derived from `AlbumDraft` at presentation time,
/// not persisted as its own thing (the Draft's `coverPhotoId`/`title`/dates/`primaryPlace` remain
/// the source of truth). See docs/specs/SPEC-REAL-ALBUM.md § 13.1.
struct AlbumCoverConfiguration: Codable, Hashable, Sendable {
    var photo: AlbumPhotoReference
    var title: String
    var subtitle: String?
    var dateText: String?
    var placeText: String?
    var styleId: String

    static let classicStyleId = "cover.classic"
}
