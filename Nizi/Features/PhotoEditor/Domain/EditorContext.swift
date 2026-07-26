//
//  EditorContext.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Where Photo Editor was opened from — never used by the editor to reach back into that
/// screen's own data, only to decide which save-scope options to offer (docs/modules/photo-editor/
/// PHOTO-EDITOR.md § 4, § 11.2).
enum EditorSourceType: String, Codable, Equatable, Sendable {
    case standalone
    case album
    case event
}

/// The only thing Album, Event, or any future caller hands to Photo Editor to open it — see
/// PHOTO-EDITOR.md § 5. `photoId`/`photoIds` are `PHAsset.localIdentifier`s, the same convention
/// every other feature in this app already uses for photo identity (`AlbumPhotoReference.
/// sourceIdentifier`, `PhotoEvent.assetIDs`) — no new photo-identity type is introduced.
struct EditorContext: Codable, Equatable, Sendable, Identifiable {
    let sourceType: EditorSourceType
    /// The Album's or Event's own id when `sourceType` is `.album`/`.event`; `nil` for `.standalone`.
    let sourceId: String?
    /// The photo the editor opens on.
    let photoId: String
    /// Every photo in scope — used when the user chooses "apply to the whole Album/Event"
    /// (§ 11.4) and, later, for in-editor photo-to-photo navigation (not part of V1).
    let photoIds: [String]

    /// `Identifiable` purely so callers can drive `.fullScreenCover(item:)` directly off an
    /// `EditorContext?` (the same idiom this app's other full-screen presentations already use for
    /// their own item payloads) — `photoId` uniquely identifies one editing session.
    var id: String { photoId }

    init(sourceType: EditorSourceType, sourceId: String?, photoId: String, photoIds: [String]) {
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.photoId = photoId
        self.photoIds = photoIds
    }

    static func standalone(photoId: String) -> EditorContext {
        EditorContext(sourceType: .standalone, sourceId: nil, photoId: photoId, photoIds: [photoId])
    }
}
