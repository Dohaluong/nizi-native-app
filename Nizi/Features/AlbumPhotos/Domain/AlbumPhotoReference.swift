//
//  AlbumPhotoReference.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Where a photo's pixels actually come from — `applePhotos` is the only source this sprint, but
/// the shape allows a future `files`/cloud source without another migration. See
/// docs/specs/SPEC-REAL-ALBUM.md § 5.2.
enum AlbumPhotoSource: String, Codable, Hashable, Sendable {
    case applePhotos
}

/// Replaces a bare `photoId: String` in `AlbumPhotoAssignment` — production code needs to know
/// exactly which library an ID belongs to, not just assume it's a `PHAsset.localIdentifier`.
struct AlbumPhotoReference: Codable, Hashable, Sendable {
    /// The Album's own internal ID for this photo slot's content — currently always equal to
    /// `sourceIdentifier` (see § 5.2), kept distinct from it so a future multi-source Album
    /// doesn't need every call site to change.
    let id: String
    let source: AlbumPhotoSource
    /// `PHAsset.localIdentifier` when `source == .applePhotos`.
    let sourceIdentifier: String
    let originalFilename: String?
}
