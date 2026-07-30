//
//  AlbumLayoutError.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Every way loading or validating the layout library can fail. Deliberately specific (not a
/// single generic case) so a failure is diagnosable from the error alone — see
/// docs/ALBUM_LAYOUT_SYSTEM.md § Validation.
enum AlbumLayoutError: Error, Equatable {
    case resourceNotFound
    case decodingFailed(String)
    case unsupportedSchemaVersion(Int)
    case duplicateLayoutId(String)
    case layoutNotFound(String)
    case invalidPhotoCount(layoutId: String)
    case slotCountMismatch(layoutId: String)
    case duplicateSlotId(layoutId: String, slotId: String)
    case duplicateSlotOrder(layoutId: String)
    case invalidCanvas(layoutId: String)
    case invalidFrame(layoutId: String, slotId: String)
    case slotOutsideCanvas(layoutId: String, slotId: String)
    case unsupportedFormat(layoutId: String)
    case aspectRatioMismatch(layoutId: String, format: AlbumPageFormat)
    case assignmentSlotNotFound(layoutId: String, slotId: String)
    case duplicateAssignmentSlot(layoutId: String, slotId: String)
    case duplicateTextBlockId(layoutId: String, textBlockId: String)
    case duplicateTextBlockOrder(layoutId: String)
    case invalidTextBlockFrame(layoutId: String, textBlockId: String)
    case textBlockOutsideCanvas(layoutId: String, textBlockId: String)
    case invalidTextBlockFontSize(layoutId: String, textBlockId: String)
}
