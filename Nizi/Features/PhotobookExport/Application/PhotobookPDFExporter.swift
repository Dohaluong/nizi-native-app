//
//  PhotobookPDFExporter.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/2/26.
//

import CoreGraphics
import UIKit

/// Exports a whole `AlbumDraft` (Cover + every real content Page, in order) into one multi-page
/// PDF file, one page's photos/bitmap/JPEG resident in memory at a time. Read-only — never
/// mutates `draft` or persists anything back through `AlbumEditActionApplying`.
///
/// Pipeline, per page: load this page's photos (async, may await a real iCloud download) → render
/// a 3000×3000 bitmap (`PhotobookPageBitmapRenderer`, fully synchronous) → JPEG-encode it →
/// write that JPEG into `workingDirectory` → release the bitmap/JPEG data before the next page.
/// Only once every page's JPEG is already on disk does the final, *entirely synchronous* step run:
/// read each JPEG back in order and draw it into its own PDF page. That separation is deliberate —
/// see the doc comment on `assemblePDF` for why the PDF-writing step specifically must never
/// straddle an `await`, and `PhotobookExportSession` for why `workingDirectory` is this exporter's
/// caller's responsibility, not its own (one temp directory per export session, never reused).
///
/// Page sequencing reuses the exact same Domain/Application functions the live Viewer already
/// uses (`AlbumCoverPageBuilder.makeViewerPage`, `DefaultAlbumViewerItemBuilder.makeItems`) — this
/// exporter never re-derives "which Page comes after which."
struct PhotobookPDFExporter {
    /// 720×720pt (10×10in at 72pt/in) — `PhotobookPageBitmapRenderer.outputSize` (3000×3000px) ÷
    /// this = 300 DPI, matching the spec exactly.
    static let pointSize = CGSize(width: 720, height: 720)
    static let jpegCompressionQuality: CGFloat = 0.93

    let layoutRepository: any AlbumLayoutRepository
    let photoLoader: any PhotobookExportPhotoLoading
    let bitmapRenderer: PhotobookPageBitmapRenderer

    init(
        layoutRepository: any AlbumLayoutRepository = BundleAlbumLayoutRepository(),
        photoLoader: any PhotobookExportPhotoLoading = ApplePhotosPhotobookExportPhotoLoader(),
        bitmapRenderer: PhotobookPageBitmapRenderer = PhotobookPageBitmapRenderer()
    ) {
        self.layoutRepository = layoutRepository
        self.photoLoader = photoLoader
        self.bitmapRenderer = bitmapRenderer
    }

    /// Cover first, then every real content Page — the same order the Viewer's own vertical
    /// scroll shows. Exposed as a static, `AlbumDraft`-only function (no PhotoKit/PDF dependency)
    /// so page count/order can be tested without touching Photos or the filesystem.
    static func exportPages(for draft: AlbumDraft, layoutRepository: any AlbumLayoutRepository) -> [AlbumViewerPage] {
        var pages = [AlbumCoverPageBuilder.makeViewerPage(from: draft, layoutRepository: layoutRepository)]
        for item in DefaultAlbumViewerItemBuilder().makeItems(from: draft) {
            if case let .page(viewerPage) = item {
                pages.append(viewerPage)
            }
        }
        return pages
    }

    /// `workingDirectory` must already exist and be empty/exclusive to this export (the caller —
    /// `PhotobookExportSession` — owns creating/naming/deleting it). Returns the finished PDF's
    /// URL, its filename derived from `draft`'s place and date (see `fileName(for:)`) inside that
    /// same directory. `onProgress` is called on the Main Actor; throws
    /// `PhotobookExportError.cancelled` if the enclosing `Task` is cancelled between pages (never
    /// mid-page, and never mid-PDF-assembly — see `assemblePDF`).
    func export(
        draft: AlbumDraft,
        workingDirectory: URL,
        onProgress: @MainActor @escaping (PhotobookExportProgress) -> Void
    ) async throws -> URL {
        let pages = Self.exportPages(for: draft, layoutRepository: layoutRepository)
        guard !pages.isEmpty else { throw PhotobookExportError.writeFailed }

        var jpegURLs: [URL] = []
        for (index, page) in pages.enumerated() {
            let pageNumber = index + 1
            try checkCancellation()

            let cgImage: CGImage
            if page.page.isBlank {
                // § "Thêm trang" — a deliberate placeholder Page with no photos yet
                // (`AlbumDraftPage.blankLayoutId`, never a real id in `AlbumLayoutRepository` by
                // design — every other reader of a Page's layout already tolerates this and falls
                // back to its own blank rendering, e.g. `AlbumPageCardView`'s "+ Add photo" card).
                // Export's own fallback is a plain white page — never the Editor's "+" affordance,
                // which is meaningless once printed — and never a fatal `.layoutMissing`, which
                // this Page's `layoutId` was never expected to resolve in the first place.
                await onProgress(PhotobookExportProgress(phase: .renderingPage(page: pageNumber, totalPages: pages.count)))
                cgImage = Self.blankPageImage()
            } else {
                let layout: AlbumPageLayout
                do {
                    layout = try layoutRepository.layout(id: page.page.layoutId)
                } catch {
                    throw PhotobookExportError.layoutMissing(pageNumber: pageNumber, layoutId: page.page.layoutId)
                }

                await onProgress(PhotobookExportProgress(phase: .renderingPage(page: pageNumber, totalPages: pages.count)))
                // Only this page's photos are ever resident — `images` goes out of scope at the
                // end of this loop iteration, well before the next page's photos are requested.
                let images = try await loadImages(for: page, layout: layout, pageNumber: pageNumber)
                try checkCancellation()
                cgImage = try bitmapRenderer.render(page: page, layout: layout, images: images)
            }
            guard cgImage.width == Int(PhotobookPageBitmapRenderer.outputSize.width),
                  cgImage.height == Int(PhotobookPageBitmapRenderer.outputSize.height)
            else {
                throw PhotobookExportError.writeFailed
            }
            guard let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: Self.jpegCompressionQuality) else {
                throw PhotobookExportError.writeFailed
            }
            let jpegURL = workingDirectory.appendingPathComponent(Self.jpegFileName(pageNumber: pageNumber))
            do {
                try jpegData.write(to: jpegURL, options: .atomic)
            } catch {
                throw PhotobookExportError.writeFailed
            }
            jpegURLs.append(jpegURL)
            // `cgImage`/`jpegData` go out of scope here — nothing from this page survives into
            // the next loop iteration except the small JPEG file already flushed to disk.
        }

        try checkCancellation()
        await onProgress(PhotobookExportProgress(phase: .finalizingPDF))

        let pdfURL = workingDirectory.appendingPathComponent(Self.fileName(for: draft))
        try Self.assemblePDF(from: jpegURLs, to: pdfURL)

        for jpegURL in jpegURLs {
            try? FileManager.default.removeItem(at: jpegURL)
        }

        return pdfURL
    }

    private func loadImages(
        for page: AlbumViewerPage, layout: AlbumPageLayout, pageNumber: Int
    ) async throws -> [String: CGImage] {
        let slotsById = Dictionary(uniqueKeysWithValues: layout.slots.map { ($0.id, $0) })
        var images: [String: CGImage] = [:]
        for assignment in page.page.assignments {
            guard let slot = slotsById[assignment.slotId] else { continue }
            // § "khi render phần hình trước khi pan bị trắng" — root cause: PhotoKit's own
            // aspectFill/aspectFit *cropping* is not deterministic enough to reproduce here.
            // `ApplePhotosAlbumPhotoProvider` (the live editor/crop sheet's own photo source) uses
            // `resizeMode = .fast`, which Apple documents as "may return an image slightly larger
            // than needed" — in practice PhotoKit hands back noticeably more of the original than
            // a tight crop, and the crop sheet's pan/zoom clamping is calibrated against *that*
            // generous, imprecise crop. `ApplePhotosPhotobookExportPhotoLoader` uses `resizeMode =
            // .exact` (deliberately, for a precise, high-quality export) — a tighter crop than
            // `.fast` gives, so panning into what `.fast` retained but `.exact` didn't produced
            // blank/white. Rather than try to replicate PhotoKit's undocumented `.fast` margin,
            // request the photo `.fit` (bounding-box only — PhotoKit performs NO crop at all, just
            // scales the whole original down to fit) so every pixel of the original is always
            // available, and let `AlbumPhotoCropGeometry.renderRect` — which already computes
            // purely from the *actual* fetched `imageSize`, agnostic to how it got that size — do
            // 100% of the real crop/pan/zoom math, exactly like it already does for on-screen
            // rendering. Sized generously (slot's own share of the 3000×3000 canvas, scaled up by
            // the user's own zoom) since `.fit` never discards content, only resolution.
            let baseSize = CGSize(
                width: slot.frame.width / layout.referenceCanvas.width * PhotobookPageBitmapRenderer.outputSize.width,
                height: slot.frame.height / layout.referenceCanvas.height * PhotobookPageBitmapRenderer.outputSize.height
            )
            let pixelSize = CGSize(width: baseSize.width * assignment.crop.scale, height: baseSize.height * assignment.crop.scale)

            do {
                images[slot.id] = try await photoLoader.loadImage(
                    reference: assignment.photo, targetPixelSize: pixelSize, contentMode: .fit, onDownloadProgress: nil
                )
            } catch is CancellationError {
                throw PhotobookExportError.cancelled
            } catch {
                throw PhotobookExportError.photoUnavailable(pageNumber: pageNumber, assetLocalIdentifier: assignment.photo.sourceIdentifier)
            }
        }
        return images
    }

    private static func jpegFileName(pageNumber: Int) -> String {
        "page-\(String(format: "%04d", pageNumber)).jpg"
    }

    /// § user request — "tự động tạo tên pdf theo địa danh và ngày tháng": the final PDF's own
    /// filename (what `ShareLink`/Files/AirDrop shows, not just an internal detail) is derived
    /// from the Album's place and date rather than a fixed "photobook.pdf" — a user exporting
    /// several photobooks needs to tell the files apart without opening each one. Place prefers
    /// the user's own edited `primaryLocationName` over the geocoded `primaryPlace.displayName`
    /// (same precedence `DefaultAlbumViewerItemBuilder.dateText`'s sibling `placeText` uses for
    /// the cover), falling back to the Album's own title, then a generic name, so this never
    /// produces an empty filename. The date uses a fixed `dd-MM-yyyy` pattern — deliberately not
    /// `EventDateRangeFormatter`/`.formatted(date:time:)`, which in several locales render dates
    /// with "/" (e.g. `7/25/2026`), a character the filesystem itself forbids.
    private static func fileName(for draft: AlbumDraft) -> String {
        let place = firstNonEmpty(draft.primaryLocationName, draft.primaryPlace?.displayName)
        let name = place ?? firstNonEmpty(draft.title) ?? "Photobook"
        let dateSuffix = draft.startDate.map { filenameDateFormatter.string(from: $0) }
        let combined = dateSuffix.map { "\(name) \($0)" } ?? name
        return "\(sanitizedForFileName(combined)).pdf"
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Strips characters the filesystem (or a recipient's, once shared) disallows/mishandles in a
    /// filename, collapses the resulting whitespace, and never returns an empty string.
    private static func sanitizedForFileName(_ raw: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = raw.components(separatedBy: disallowed).joined(separator: "-")
        let collapsed = cleaned.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Photobook" : trimmed
    }

    /// A pure white 3000×3000 canvas — `page.page.isBlank`'s own fallback, never the Editor's
    /// "+ Add photo" placeholder (that affordance has no meaning on a printed/exported page).
    private static func blankPageImage() -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: PhotobookPageBitmapRenderer.outputSize, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: PhotobookPageBitmapRenderer.outputSize))
        }
        return image.cgImage!
    }

    private func checkCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw PhotobookExportError.cancelled
        }
    }

    /// Entirely synchronous, start to finish — every JPEG this reads was already fully written to
    /// disk by the (async) loop above, so nothing here ever suspends. That is exactly what makes
    /// `UIGraphicsBeginPDFContextToFile`/`UIGraphicsBeginPDFPageWithInfo` safe to use again: their
    /// "current PDF context" is thread-local, and Swift's cooperative thread pool does not
    /// guarantee an `async` function resumes on the same thread it suspended on — the original,
    /// buggy version of this exporter called `UIGraphicsBeginPDFContextToFile` once, then `await`ed
    /// several photo loads, then called `UIGraphicsGetCurrentContext()` afterward, which
    /// intermittently returned `nil` whenever the Task happened to resume on a different thread.
    /// Confining every `UIGraphicsBegin…`/`UIGraphicsGetCurrentContext` call to one unbroken
    /// synchronous span removes that failure mode entirely, regardless of which thread this
    /// function happens to run on.
    ///
    /// § "phủ toàn bộ PDF page, không có viền trắng" — each JPEG is drawn at exactly
    /// `CGRect(origin: .zero, size: pointSize)`, the PDF page's own full bounds; no margin, no
    /// additional crop.
    private static func assemblePDF(from jpegURLs: [URL], to pdfURL: URL) throws {
        guard UIGraphicsBeginPDFContextToFile(pdfURL.path, .zero, nil) else {
            throw PhotobookExportError.writeFailed
        }
        defer { UIGraphicsEndPDFContext() }

        let pageRect = CGRect(origin: .zero, size: pointSize)
        for jpegURL in jpegURLs {
            guard let data = try? Data(contentsOf: jpegURL), let image = UIImage(data: data) else {
                throw PhotobookExportError.writeFailed
            }
            UIGraphicsBeginPDFPageWithInfo(pageRect, nil)
            image.draw(in: pageRect)
        }
    }
}
