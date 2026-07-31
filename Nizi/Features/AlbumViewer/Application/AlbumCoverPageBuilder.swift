//
//  AlbumCoverPageBuilder.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import Foundation

/// § user request — "trang bìa sẽ có cấu trúc như trang ruột": synthesizes a Cover as an
/// `AlbumViewerPage` so any `AlbumPageCardView`/`AlbumPageRenderer` call site can render it
/// exactly like a content Page (same corner radius, same crop/text-block gestures if wired up) —
/// shared by `AlbumPageViewer` (the interactive editor) and `AlbumDetailView` (the read-only
/// hero), so neither has to re-derive this synthesis on its own.
enum AlbumCoverPageBuilder {
    /// The fixed layout every Album's cover uses by default — authored in the Layout Studio with
    /// a `gradientOverlay` (for text legibility) and 3 `kind`-tagged text blocks (title/subtitle/
    /// paragraph), exactly like any content-Page layout. `AlbumDraft.coverLayoutId` overrides this
    /// once a user picks something else (§ user request — "sau này có thể thay layout khác").
    static let layoutId = "square.1.cover"
    /// Never a real id in `draft.spreads` (Spread/Page ids are UUID-shaped) — safe as a fixed
    /// sentinel for the synthesized `AlbumDraftPage.id`/`AlbumViewerPage.id`, and what callers
    /// check against to tell "this is the cover" apart from a real content Page.
    static let pageId = "cover"

    /// § user request — "Với các phần nội dung title, subtitle, và paragraph tương ứng với những
    /// nội dung sẵn có của Album (Tên, ngày tháng, địa điểm)": the Cover's title/subtitle/
    /// paragraph text blocks (matched by `AlbumTextBlock.kind`, not by id — the Studio-authored
    /// layout could rename/reorder its own block ids freely) are seeded from the Album's own
    /// `title`/date/location the *first* time they're shown; once a user edits one via the same
    /// tap-to-edit-text flow content Pages already use, `draft.coverTextAssignments` holds the
    /// real value from then on. A layout missing some (or all) `kind`s — "nếu các yếu tố khác ...
    /// không có thì đơn giản là bỏ qua" — simply produces fewer text assignments; nothing here
    /// requires all three to be present.
    static func makeViewerPage(from draft: AlbumDraft, layoutRepository: AlbumLayoutRepository) -> AlbumViewerPage {
        let resolvedLayoutId = draft.coverLayoutId ?? layoutId
        let layout = try? layoutRepository.layout(id: resolvedLayoutId)
        let coverSlotId = layout?.slots.first?.id ?? "photo-1"
        let assignment = AlbumPhotoAssignment(
            id: pageId, slotId: coverSlotId,
            photo: draft.coverPhotoReference, crop: draft.coverPhotoCrop ?? .centered
        )
        let textAssignments = (layout?.textBlocks ?? []).map { block in
            draft.coverTextAssignments?.first { $0.textBlockId == block.id }
                ?? AlbumTextAssignment(
                    id: "\(pageId)-\(block.id)", textBlockId: block.id, text: defaultText(for: block.kind, draft: draft),
                    horizontalAlignment: block.horizontalAlignment, verticalAlignment: block.verticalAlignment,
                    fontFamily: block.fontFamily, fontSize: block.fontSize, fontStyle: block.fontStyle, textColor: block.textColor
                )
        }
        let page = AlbumDraftPage(
            id: pageId, order: -1, layoutId: resolvedLayoutId, format: .square,
            assignments: [assignment], sourceEventIds: [], textAssignments: textAssignments
        )
        return AlbumViewerPage(
            id: pageId, page: page, pageNumber: 0, totalPageCount: 0,
            spreadId: pageId, spreadIndex: -1, positionInSpread: .left
        )
    }

    private static func defaultText(for kind: AlbumTextBlockKind, draft: AlbumDraft) -> String {
        switch kind {
        case .title:
            return draft.title
        case .subtitle:
            return DefaultAlbumViewerItemBuilder.dateText(draft: draft) ?? ""
        case .paragraph:
            return draft.primaryLocationName ?? draft.primaryPlace?.displayName ?? ""
        }
    }
}
