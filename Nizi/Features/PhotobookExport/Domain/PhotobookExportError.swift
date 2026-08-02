//
//  PhotobookExportError.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/2/26.
//

import Foundation

/// Fails fast, with enough context to name exactly which page/photo the export couldn't finish
/// with — "thông báo rõ nếu ảnh iCloud chưa tải được" (a clear notice when an iCloud photo
/// couldn't be downloaded), not a generic "export failed."
enum PhotobookExportError: Error, Equatable {
    /// PhotoKit returned no image (or the fetch failed/timed out) for one photo on one page —
    /// most commonly an iCloud-only asset whose download couldn't complete (no network, or the
    /// asset has since been deleted from the library). `pageNumber` is 1-based and matches what
    /// the progress UI already shows the user, so the error message can point at the same page.
    case photoUnavailable(pageNumber: Int, assetLocalIdentifier: String)
    /// The layout a page references no longer exists in the bundled layout library — should not
    /// happen for a Draft produced by this app's own planner, but a corrupted/hand-edited Draft
    /// must fail clearly rather than silently render a blank page.
    case layoutMissing(pageNumber: Int, layoutId: String)
    /// The per-session temp directory (`PhotobookExport/<session-id>/`) couldn't be created —
    /// nothing has been written yet at this point, a pure filesystem-level failure.
    case sessionSetupFailed
    /// Either one page's bitmap/JPEG couldn't be produced (`CGContext`/`UIImage`/JPEG-encode
    /// failure), or the final synchronous PDF-assembly step failed to open/write the output file —
    /// a filesystem/Core Graphics failure, not a content one.
    case writeFailed
    case cancelled
}

extension PhotobookExportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .photoUnavailable(pageNumber, _):
            return localizedString(
                "photobook.export.error.photo_unavailable",
                defaultValue: "Trang \(pageNumber): một ảnh chưa tải xong từ iCloud. Kiểm tra kết nối mạng rồi thử lại."
            )
        case let .layoutMissing(pageNumber, _):
            return localizedString(
                "photobook.export.error.layout_missing",
                defaultValue: "Trang \(pageNumber): không tìm thấy bố cục trang."
            )
        case .sessionSetupFailed, .writeFailed:
            return localizedString(
                "photobook.export.error.write_failed",
                defaultValue: "Không thể tạo file PDF."
            )
        case .cancelled:
            return localizedString(
                "photobook.export.error.cancelled",
                defaultValue: "Đã huỷ xuất PDF."
            )
        }
    }
}
