//
//  AlbumDraft.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// One Album page: which layout it uses and which photo fills which slot. Reuses
/// `AlbumPhotoAssignment`/`AlbumPageFormat` from `Features/AlbumLayout/Domain` directly — a page
/// stores only `layoutId`, never the layout's geometry (see
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 27: "Không lưu toàn bộ layout JSON vào từng Page").
///
/// `heroPhotoId`/`primaryPlace`/`layoutScore`/`assignmentScore` (docs/specs/SPEC-ALBUM-PLANNER.md
/// § 8.4) are all `Optional` so a draft encoded before this field existed still decodes cleanly
/// (§ 12: "Không xóa dữ liệu Draft cũ một cách im lặng") — they're diagnostic/UI metadata, not
/// required for the Layout Renderer, which only ever reads `layoutId`/`assignments`.
struct AlbumDraftPage: Identifiable, Codable, Hashable {
    let id: String
    /// `var`, not `let` — `AlbumEditActionApplying.removeSpread` renumbers remaining
    /// Spreads/Pages after a removal so `order` stays a clean, gap-free sequence.
    var order: Int

    var layoutId: String
    var format: AlbumPageFormat

    var assignments: [AlbumPhotoAssignment]

    var sourceEventIds: [String]

    var heroPhotoId: String?
    var primaryPlace: PhotoPlace?
    var layoutScore: Double?
    var assignmentScore: Double?

    /// § user request "Thêm chữ" — real, user-typed content for this Page's layout's text blocks
    /// (keyed by `AlbumTextAssignment.textBlockId`). Decoded via `decodeIfPresent(...) ?? []` (not
    /// `Optional` like the fields above — an empty array is already exactly "nothing typed yet,"
    /// no separate `nil` state needed) so a draft encoded before this feature existed still
    /// decodes cleanly, the same posture `AlbumPageLayout.textBlocks` already takes.
    var textAssignments: [AlbumTextAssignment]

    init(
        id: String, order: Int, layoutId: String, format: AlbumPageFormat,
        assignments: [AlbumPhotoAssignment], sourceEventIds: [String],
        heroPhotoId: String? = nil, primaryPlace: PhotoPlace? = nil,
        layoutScore: Double? = nil, assignmentScore: Double? = nil,
        textAssignments: [AlbumTextAssignment] = []
    ) {
        self.id = id
        self.order = order
        self.layoutId = layoutId
        self.format = format
        self.assignments = assignments
        self.sourceEventIds = sourceEventIds
        self.heroPhotoId = heroPhotoId
        self.primaryPlace = primaryPlace
        self.layoutScore = layoutScore
        self.assignmentScore = assignmentScore
        self.textAssignments = textAssignments
    }

    /// § user request — "Thêm trang ... tạo ra 1 trang trắng. Click vào có thể thêm ảnh sau": the
    /// sentinel `layoutId` for a Page with no photos yet that should still show up in the Viewer
    /// as a tappable "add a photo" placeholder — as opposed to a genuinely empty Page with 0
    /// assignments that `AlbumEditActionApplying.removePage`/`addBlankPage` leave sitting
    /// unfilled purely as internal Spread padding (any other `layoutId`, invisible — see
    /// `AlbumViewerItemBuilder`). Never a real id in `AlbumLayoutRepository`; every read site that
    /// resolves a Page's actual layout geometry already tolerates `repository.layout(id:)` failing
    /// (falls back to a placeholder), so this never needs special-casing there.
    static let blankLayoutId = "blank"
    var isBlank: Bool { layoutId == Self.blankLayoutId }

    private enum CodingKeys: String, CodingKey {
        case id, order, layoutId, format, assignments, sourceEventIds
        case heroPhotoId, primaryPlace, layoutScore, assignmentScore, textAssignments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        layoutId = try container.decode(String.self, forKey: .layoutId)
        format = try container.decode(AlbumPageFormat.self, forKey: .format)
        assignments = try container.decode([AlbumPhotoAssignment].self, forKey: .assignments)
        sourceEventIds = try container.decode([String].self, forKey: .sourceEventIds)
        heroPhotoId = try container.decodeIfPresent(String.self, forKey: .heroPhotoId)
        primaryPlace = try container.decodeIfPresent(PhotoPlace.self, forKey: .primaryPlace)
        layoutScore = try container.decodeIfPresent(Double.self, forKey: .layoutScore)
        assignmentScore = try container.decodeIfPresent(Double.self, forKey: .assignmentScore)
        textAssignments = try container.decodeIfPresent([AlbumTextAssignment].self, forKey: .textAssignments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(order, forKey: .order)
        try container.encode(layoutId, forKey: .layoutId)
        try container.encode(format, forKey: .format)
        try container.encode(assignments, forKey: .assignments)
        try container.encode(sourceEventIds, forKey: .sourceEventIds)
        try container.encodeIfPresent(heroPhotoId, forKey: .heroPhotoId)
        try container.encodeIfPresent(primaryPlace, forKey: .primaryPlace)
        try container.encodeIfPresent(layoutScore, forKey: .layoutScore)
        try container.encodeIfPresent(assignmentScore, forKey: .assignmentScore)
        try container.encode(textAssignments, forKey: .textAssignments)
    }
}

/// Two consecutive pages the planner reasons about together (§ 2.3) — never fewer, never more.
struct AlbumDraftSpread: Identifiable, Codable, Hashable {
    let id: String
    /// `var`, not `let` — `AlbumEditActionApplying.removeSpread` renumbers remaining
    /// Spreads/Pages after a removal so `order` stays a clean, gap-free sequence.
    var order: Int

    let sourceEventIds: [String]

    var leftPage: AlbumDraftPage
    var rightPage: AlbumDraftPage

    /// § 8.3 — derived from the pages' own assignment counts rather than stored redundantly, so
    /// it can never drift out of sync and never needs a decode fallback.
    var photoCount: Int {
        leftPage.assignments.count + rightPage.assignments.count
    }

    var orientationSummary: AlbumPhotoOrientationSummary?
    var primaryPlace: PhotoPlace?
    var heroPhotoId: String?
    var planningScore: Double?
}

/// One Event this Album drew photos from, plus how many of its photos ended up in the Album —
/// summary-only, not a full copy of the Event (§ 8.2: "Không lưu lại toàn bộ ảnh trong source
/// event metadata").
struct AlbumSourceEvent: Identifiable, Codable, Hashable {
    let id: String
    let title: String?
    let selectedPhotoCount: Int

    let startDate: Date?
    let endDate: Date?
    let place: PhotoPlace?
}

struct AlbumDraft: Identifiable, Codable, Hashable {
    let id: String

    var title: String
    var subtitle: String?

    var coverPhotoId: String

    var startDate: Date?
    var endDate: Date?

    var primaryLocationName: String?
    var primaryPlace: PhotoPlace?

    var sourceEvents: [AlbumSourceEvent]

    var spreads: [AlbumDraftSpread]

    var createdAt: Date
    /// `nil` for a draft that predates edit support, or one never updated since creation
    /// (docs/specs/SPEC-REAL-ALBUM.md § 27.3: preserve `createdAt`, update this on every Save).
    var updatedAt: Date?

    /// `nil` means this draft predates planning versioning; a draft newly created by
    /// `AlbumDraftPlanner` always sets this to `1` explicitly (§ 8.1).
    var planningVersion: Int?
    var planningLog: AlbumPlanningLog?

    /// § user request — "trang bìa sẽ có cấu trúc như trang ruột ... chức năng chạm vào để crop
    /// ảnh ... tương tự như trang khác": the cover photo's crop, unified with the same
    /// `AlbumPhotoAssignment.crop`-shaped machinery every content-Page photo already has. `nil`
    /// means never customized — same "centered, no adjustment" default `AlbumPhotoCrop.centered`
    /// itself is.
    var coverPhotoCrop: AlbumPhotoCrop? = nil

    /// § user request — "square.1.cover là layout mặc định cho ảnh bìa, sau này có thể thay layout
    /// khác": `nil` means the fixed default (`AlbumPageViewer.coverLayoutId`, `"square.1.cover"`) —
    /// mirrors `AlbumDraftPage.layoutId`, minus the non-optionality (a content Page always has a
    /// real layout from the moment it's planned; the cover only needs a stored override once a
    /// user actually picks something different from the default).
    var coverLayoutId: String? = nil

    /// § user request — the cover's title/subtitle/paragraph text blocks (matched by
    /// `AlbumTextBlock.kind` in the `square.1.cover` layout), independently editable exactly like
    /// a content Page's `AlbumDraftPage.textAssignments` once tapped — seeded the *first* time
    /// from the Album's own `title`/date/location ("tương ứng với những nội dung sẵn có của
    /// Album: Tên, ngày tháng, địa điểm" — see `AlbumPageViewer.defaultCoverText`). Kept
    /// `Optional` (not `[]`-defaulted) purely so `AlbumDraft` doesn't need its own custom
    /// `Codable` just for this one field's legacy fallback — every read site treats `nil` and
    /// `[]` identically.
    var coverTextAssignments: [AlbumTextAssignment]? = nil

    var numberOfPages: Int {
        spreads.count * 2
    }

    /// Derived, never stored redundantly — always exactly the sum of every page's assignments.
    var totalPhotoCount: Int {
        spreads.reduce(0) { $0 + $1.photoCount }
    }

    /// Every `coverPhotoId` in this codebase has always come from `AlbumPlanningPhoto.id`, which
    /// is always a `PHAsset.localIdentifier` (see `PHAssetPlanningPhotoAdapter`) — so this is a
    /// safe derivation, not a stored migration, matching the same reasoning
    /// `AlbumPhotoAssignment.photoId`'s legacy init uses (docs/specs/SPEC-REAL-ALBUM.md § 6).
    var coverPhotoReference: AlbumPhotoReference {
        AlbumPhotoReference(id: coverPhotoId, source: .applePhotos, sourceIdentifier: coverPhotoId, originalFilename: nil)
    }
}
