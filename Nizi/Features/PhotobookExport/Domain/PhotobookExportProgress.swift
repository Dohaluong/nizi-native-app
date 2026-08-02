//
//  PhotobookExportProgress.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/2/26.
//

import Foundation

/// Which of the export's two real phases is currently in flight — § user request: progress must
/// reflect "Đang tạo trang X/Y" (rendering, per page) and "Đang hoàn thiện PDF" (the final,
/// single-shot assembly step).
enum PhotobookExportPhase: Equatable {
    /// Loading (if already local) and rendering `page` into its bitmap/JPEG.
    case renderingPage(page: Int, totalPages: Int)
    /// Every page's JPEG is on disk; assembling them into the final PDF (fast, but real work —
    /// still worth its own message rather than looking stuck at "page N of N").
    case finalizingPDF
}

struct PhotobookExportProgress: Equatable {
    let phase: PhotobookExportPhase

    /// `nil` while finalizing the PDF — that step has no natural "page N of M" position of its
    /// own to show a determinate bar for.
    var fraction: Double? {
        switch phase {
        case let .renderingPage(page, totalPages):
            guard totalPages > 0 else { return 0 }
            return Double(page) / Double(totalPages)
        case .finalizingPDF:
            return nil
        }
    }
}
