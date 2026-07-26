//
//  MDAlbumDraft.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import SwiftData

/// Minimal Album persistence — this project has no full Album module yet (§ 27: "Nếu chưa có
/// model Album đầy đủ, cần tạo cấu trúc tối thiểu"). The whole `AlbumDraft` (id, cover, title,
/// dates, location, source Events, Spreads/Pages/`layoutId`s/assignments, place, importance,
/// planning log — docs/specs/SPEC-ALBUM-PLANNER.md § 12) is stored as encoded JSON in
/// `encodedDraft`; a handful of fields are duplicated as plain columns purely so a list screen
/// can query/sort without decoding every row (docs/specs/SPEC-REAL-ALBUM.md § 27.2). Crucially,
/// `AlbumDraftPage.layoutId` is just a `String` reference — no layout geometry is ever
/// duplicated into this store (§ 27.1: "Không lưu toàn bộ layout JSON vào từng Page"); geometry
/// always comes from `AlbumLayoutRepository` at render time. Not a relational store — Page
/// content isn't flattened into its own rows/columns (§ 27.2: "Không duplicate toàn bộ Page data
/// thành flat columns").
///
/// All new columns default to a harmless value so SwiftData's lightweight migration can add them
/// to any existing row without data loss (§ 12/§ 27: "Không xóa dữ liệu Draft cũ một cách im
/// lặng"); `encodedDraft` itself decodes safely too, since every new `AlbumDraft` field is
/// `Optional` or computed (see `AlbumDraft.swift`).
@Model
final class MDAlbumDraft {
    @Attribute(.unique) var draftID: String
    var title: String
    var coverPhotoID: String
    var coverPhotoIdentifier: String = ""
    var primaryPlaceName: String?
    var startDate: Date?
    var endDate: Date?
    var photoCount: Int = 0
    var spreadCount: Int = 0
    var planningVersion: Int?
    var createdAt: Date
    var updatedAt: Date?
    var encodedDraft: Data

    init(draft: AlbumDraft) throws {
        draftID = draft.id
        title = draft.title
        coverPhotoID = draft.coverPhotoId
        coverPhotoIdentifier = draft.coverPhotoReference.sourceIdentifier
        primaryPlaceName = draft.primaryPlace?.displayName
        startDate = draft.startDate
        endDate = draft.endDate
        photoCount = draft.totalPhotoCount
        spreadCount = draft.spreads.count
        planningVersion = draft.planningVersion
        createdAt = draft.createdAt
        updatedAt = draft.updatedAt
        encodedDraft = try JSONEncoder().encode(draft)
    }

    func apply(_ draft: AlbumDraft) throws {
        title = draft.title
        coverPhotoID = draft.coverPhotoId
        coverPhotoIdentifier = draft.coverPhotoReference.sourceIdentifier
        primaryPlaceName = draft.primaryPlace?.displayName
        startDate = draft.startDate
        endDate = draft.endDate
        photoCount = draft.totalPhotoCount
        spreadCount = draft.spreads.count
        planningVersion = draft.planningVersion
        // createdAt is deliberately never overwritten here.
        updatedAt = draft.updatedAt
        encodedDraft = try JSONEncoder().encode(draft)
    }

    func decodedDraft() throws -> AlbumDraft {
        try JSONDecoder().decode(AlbumDraft.self, from: encodedDraft)
    }
}
