//
//  AlbumPageContent.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Which photo (`photo`) fills which slot (`slotId`) — explicit assignment, never an implicit
/// array-position mapping. This is what lets a user swap two photos between slots without
/// touching the layout, and lets validation catch a missing/duplicate/dangling slot reference.
/// See docs/ALBUM_LAYOUT_SYSTEM.md § Album page content and
/// docs/specs/SPEC-REAL-ALBUM.md § 5.3–5.4/§ 6.
///
/// `photo`/`crop` replaced a bare `photoId: String` — `photoId` is kept as a computed property
/// (spec's own suggested compromise: "có thể tạm giữ computed property... Không lưu trùng hai ID
/// trong JSON") so the many existing call sites that only *read* `.photoId` don't need to change.
/// Decoding accepts *either* the old `{"photoId": "..."}` shape or the new `{"photo": {...}}`
/// shape — never silently drops an old Draft (§ 6). The migration assumption (old `photoId` was
/// always a `PHAsset.localIdentifier`) is explicit here, not hidden.
struct AlbumPhotoAssignment: Identifiable, Codable, Hashable {
    let id: String
    let slotId: String
    var photo: AlbumPhotoReference
    var crop: AlbumPhotoCrop

    var photoId: String { photo.id }

    /// Legacy-shaped construction — treats `photoId` as an Apple Photos local identifier, matching
    /// every existing call site in this codebase (§ 6: "chỉ đúng nếu trước đây `photoId` được lấy
    /// từ `PHAsset.localIdentifier`," which is the case here — see `PHAssetPlanningPhotoAdapter`).
    init(id: String, slotId: String, photoId: String) {
        self.id = id
        self.slotId = slotId
        photo = AlbumPhotoReference(id: photoId, source: .applePhotos, sourceIdentifier: photoId, originalFilename: nil)
        crop = .centered
    }

    init(id: String, slotId: String, photo: AlbumPhotoReference, crop: AlbumPhotoCrop = .centered) {
        self.id = id
        self.slotId = slotId
        self.photo = photo
        self.crop = crop
    }

    private enum CodingKeys: String, CodingKey {
        case id, slotId, photo, crop, photoId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slotId = try container.decode(String.self, forKey: .slotId)
        if let decodedPhoto = try container.decodeIfPresent(AlbumPhotoReference.self, forKey: .photo) {
            photo = decodedPhoto
        } else {
            let legacyPhotoId = try container.decode(String.self, forKey: .photoId)
            photo = AlbumPhotoReference(id: legacyPhotoId, source: .applePhotos, sourceIdentifier: legacyPhotoId, originalFilename: nil)
        }
        crop = try container.decodeIfPresent(AlbumPhotoCrop.self, forKey: .crop) ?? .centered
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(slotId, forKey: .slotId)
        try container.encode(photo, forKey: .photo)
        try container.encode(crop, forKey: .crop)
    }
}

/// One page's real content: which layout it uses and what's assigned to each of that layout's
/// slots. Contains no layout coordinates — those live only in the `AlbumPageLayout` looked up by
/// `layoutId`.
struct AlbumPageContent: Identifiable, Codable, Hashable {
    let id: String
    var layoutId: String
    var format: AlbumPageFormat
    var assignments: [AlbumPhotoAssignment]
}
