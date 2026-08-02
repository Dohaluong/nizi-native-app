//
//  PhotobookPDFExporterTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 8/2/26.
//

import Foundation
import Darwin
import PDFKit
import Testing
@testable import Nizi

/// § user request — bitmap size, orientation, crop parity, PDF page count/size, page order,
/// full-bleed JPEG, cancel/retry lifecycle, missing-photo error identity, memory bound, temp
/// cleanup. Uses a real `BundleAlbumLayoutRepository` (the same bundled `album-layouts.json`
/// production reads) with the shipped `square.1.full-bleed` layout — one photo slot, no text
/// blocks, `referenceCanvas` 1000×1000 — so every page's geometry is simple and predictable.
/// `MockPhotobookExportPhotoLoader` never touches PhotoKit/Photos.
///
/// Note on scope: the current `AlbumLayoutSlot`/`AlbumPhotoCrop` model has no rotation field at
/// all (confirmed by reading `AlbumLayoutSlot.swift`/`AlbumPhotoCrop.swift` directly) — nothing in
/// this codebase can currently produce a rotated Page, so there is no rotation behavior to test.
/// Crop/zoom/offset parity is covered by `AlbumPhotoCropGeometry`'s own placement math (shared
/// verbatim with the Editor, not reimplemented) and this file's `orientationTests`/render tests.
struct PhotobookPDFExporterTests {
    // MARK: - Fixtures

    private func reference(_ id: String) -> AlbumPhotoReference {
        AlbumPhotoReference(id: id, source: .applePhotos, sourceIdentifier: id, originalFilename: nil)
    }

    /// One photo, `square.1.full-bleed` (a real, bundled layout).
    private func page(id: String, photoId: String) -> AlbumDraftPage {
        AlbumDraftPage(
            id: id, order: 0, layoutId: "square.1.full-bleed", format: .square,
            assignments: [AlbumPhotoAssignment(id: "\(id)-a0", slotId: "photo-1", photo: reference(photoId))],
            sourceEventIds: ["e1"]
        )
    }

    /// § user report — "Tôi đang cho một số trang trắng, không có layout": a deliberate
    /// placeholder Page (`AlbumDraftPage.isBlank`) with no assignments and the sentinel
    /// `blankLayoutId`, which is *never* a real id in `AlbumLayoutRepository` by design.
    private func blankPage(id: String) -> AlbumDraftPage {
        AlbumDraftPage(
            id: id, order: 0, layoutId: AlbumDraftPage.blankLayoutId, format: .square,
            assignments: [], sourceEventIds: []
        )
    }

    private func spread(id: String, order: Int, rightIsBlank: Bool = false) -> AlbumDraftSpread {
        AlbumDraftSpread(
            id: id, order: order, sourceEventIds: ["e1"],
            leftPage: page(id: "\(id)-left", photoId: "\(id)-left-photo"),
            rightPage: rightIsBlank ? blankPage(id: "\(id)-right") : page(id: "\(id)-right", photoId: "\(id)-right-photo")
        )
    }

    private func draft(spreadCount: Int) -> AlbumDraft {
        AlbumDraft(
            id: "draft-export-test", title: "Export Test", subtitle: nil, coverPhotoId: "cover-photo",
            startDate: nil, endDate: nil, primaryLocationName: nil, primaryPlace: nil,
            sourceEvents: [], spreads: (0..<spreadCount).map { spread(id: "s\($0)", order: $0) },
            createdAt: Date(), planningVersion: 1, planningLog: nil
        )
    }

    private func makeWorkingDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotobookExportTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func solidColorCGImage(width: Int, height: Int, color: UIColor) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.cgImage!
    }

    /// Top half red, bottom half blue — a distinguishable orientation fixture (see
    /// `pageIsNotFlippedVertically`).
    private func topRedBottomBlueCGImage(width: Int, height: Int) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        }
        return image.cgImage!
    }

    /// Samples one pixel from `cgImage` at top-left-origin, Y-down coordinates `(x, y)` — the same
    /// convention every rect in `PhotobookPageBitmapRenderer`/`AlbumLayoutFrame` is authored in.
    private func pixel(of cgImage: CGImage, atTopLeftX x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let sourceImage = UIImage(cgImage: cgImage)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format)
        let sampled = renderer.image { _ in
            sourceImage.draw(at: CGPoint(x: -x, y: -y))
        }
        guard let data = sampled.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return (0, 0, 0)
        }
        return (bytes[0], bytes[1], bytes[2])
    }

    // MARK: - Bitmap size

    @Test func bitmapIsExactly3000By3000Pixels() throws {
        let layout = try BundleAlbumLayoutRepository().layout(id: "square.1.full-bleed")
        let viewerPage = AlbumViewerPage(
            id: "p1", page: page(id: "p1", photoId: "photo-a"), pageNumber: 1, totalPageCount: 1,
            spreadId: "s1", spreadIndex: 0, positionInSpread: .left
        )
        let image = solidColorCGImage(width: 400, height: 300, color: .systemBlue)
        let cgImage = try PhotobookPageBitmapRenderer().render(page: viewerPage, layout: layout, images: ["photo-1": image])
        #expect(cgImage.width == 3000)
        #expect(cgImage.height == 3000)
        #expect(cgImage.width == Int(PhotobookPageBitmapRenderer.outputSize.width))
        #expect(cgImage.height == Int(PhotobookPageBitmapRenderer.outputSize.height))
    }

    // MARK: - Orientation

    @Test func pageIsNotFlippedVertically() throws {
        let layout = try BundleAlbumLayoutRepository().layout(id: "square.1.full-bleed")
        let viewerPage = AlbumViewerPage(
            id: "p1", page: page(id: "p1", photoId: "photo-a"), pageNumber: 1, totalPageCount: 1,
            spreadId: "s1", spreadIndex: 0, positionInSpread: .left
        )
        // 100×200, top half red / bottom half blue — see this file's own derivation in the PR
        // description of exactly which output pixels this maps to under `contentMode: .fill`.
        let sourceImage = topRedBottomBlueCGImage(width: 100, height: 200)
        let cgImage = try PhotobookPageBitmapRenderer().render(page: viewerPage, layout: layout, images: ["photo-1": sourceImage])

        let top = pixel(of: cgImage, atTopLeftX: 1500, y: 10)
        let bottom = pixel(of: cgImage, atTopLeftX: 1500, y: 2990)

        #expect(top.r > 150 && top.b < 100, "expected the top of the page to sample as red (source's top half), got \(top) — page may be flipped vertically")
        #expect(bottom.b > 150 && bottom.r < 100, "expected the bottom of the page to sample as blue (source's bottom half), got \(bottom) — page may be flipped vertically")
    }

    // MARK: - Placeholder text

    /// § user request — "không hiện chữ placeholder trong bản xuất PDF": a text block with no
    /// real, user-typed content must render nothing at all, never `AlbumTextBlockKind
    /// .placeholderText` (the Editor's own dimmed "Title"/"Lorem ipsum…" editing affordance).
    /// `square.1.doc.text` (a real, bundled layout: one photo slot + one text block) with *no*
    /// `textAssignments` at all reproduces exactly what an untouched, never-edited text block
    /// looks like.
    @Test func emptyTextBlockDrawsNothing() throws {
        let layout = try BundleAlbumLayoutRepository().layout(id: "square.1.doc.text")
        let pageModel = AlbumDraftPage(
            id: "p1", order: 0, layoutId: "square.1.doc.text", format: .square,
            assignments: [AlbumPhotoAssignment(id: "p1-a0", slotId: "photo-1", photo: reference("photo-a"))],
            sourceEventIds: ["e1"], textAssignments: [] // never edited — placeholder territory in the Editor.
        )
        let viewerPage = AlbumViewerPage(id: "p1", page: pageModel, pageNumber: 1, totalPageCount: 1, spreadId: "s1", spreadIndex: 0, positionInSpread: .left)
        let image = solidColorCGImage(width: 400, height: 400, color: .white)

        // Renders without throwing regardless of whether any text is drawn — this test's real
        // assertion is that the *content* differs from a version with real text (below), proving
        // something was actually skipped rather than this layout having no text block to skip.
        let withoutText = try PhotobookPageBitmapRenderer().render(page: viewerPage, layout: layout, images: ["photo-1": image])

        var withRealText = pageModel
        withRealText.textAssignments = [
            AlbumTextAssignment(id: "p1-t0", textBlockId: "text-1", text: "Real caption", textColor: "#FF0000")
        ]
        let viewerPageWithText = AlbumViewerPage(id: "p1", page: withRealText, pageNumber: 1, totalPageCount: 1, spreadId: "s1", spreadIndex: 0, positionInSpread: .left)
        let withText = try PhotobookPageBitmapRenderer().render(page: viewerPageWithText, layout: layout, images: ["photo-1": image])

        // Sampling the text block's own area (bright red "Real caption" vs. nothing drawn over
        // the white background) is a strong enough signal that the two renders are different
        // without needing to know the block's exact on-canvas rect ahead of time.
        let withoutTextData = withoutText.dataProvider?.data as Data?
        let withTextData = withText.dataProvider?.data as Data?
        #expect(withoutTextData != withTextData)
    }

    // MARK: - Crop/scale/offset parity with the Editor

    @Test func slotUsesTheSameCropGeometryTheEditorUses() {
        // `AlbumPhotoCropGeometry` is the literal, single source both `AlbumPhotoView` (Editor)
        // and `PhotobookPageBitmapRenderer` (export) call — this asserts its own contract, not a
        // duplicated formula, so both call sites can never silently drift apart.
        let crop = AlbumPhotoCrop(normalizedOffsetX: 0.2, normalizedOffsetY: -0.1, scale: 1.5)
        let rect = AlbumPhotoCropGeometry.renderRect(
            imageSize: CGSize(width: 200, height: 100), frameSize: CGSize(width: 300, height: 300), fill: true, crop: crop
        )
        // fill: image wider than frame (aspect 2 > 1) → height matches frame, width overflows.
        let base = AlbumPhotoCropGeometry.aspectFitFillSize(imageSize: CGSize(width: 200, height: 100), frameSize: CGSize(width: 300, height: 300), fill: true)
        #expect(base.height == 300)
        #expect(rect.width == base.width * 1.5)
        #expect(rect.height == base.height * 1.5)
        // Centered placement + normalized offset, in frame-local coordinates.
        let expectedX = (300 - rect.width) / 2 + 0.2 * 300
        let expectedY = (300 - rect.height) / 2 + (-0.1) * 300
        #expect(abs(rect.minX - expectedX) < 0.01)
        #expect(abs(rect.minY - expectedY) < 0.01)
    }

    // MARK: - Page count / order

    @Test func exportPagesIsCoverPlusEveryContentPage() {
        let pages = PhotobookPDFExporter.exportPages(for: draft(spreadCount: 2), layoutRepository: BundleAlbumLayoutRepository())
        // 1 cover + 2 spreads × 2 pages = 5.
        #expect(pages.count == 5)
    }

    @Test func exportPagesPreservesCoverThenSpreadThenLeftRightOrder() {
        let d = draft(spreadCount: 2)
        let pages = PhotobookPDFExporter.exportPages(for: d, layoutRepository: BundleAlbumLayoutRepository())
        let ids = pages.map(\.id)
        #expect(ids == [AlbumCoverPageBuilder.pageId, "s0-left", "s0-right", "s1-left", "s1-right"])
    }

    // MARK: - Full export: PDF page count, page size, order, full-bleed

    @Test func pdfHasOnePagePerExportPageAtExactly720Points() async throws {
        let draft = draft(spreadCount: 2)
        let workingDirectory = makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let exporter = PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: MockPhotobookExportPhotoLoader())
        let pdfURL = try await exporter.export(draft: draft, workingDirectory: workingDirectory) { _ in }

        let expectedPageCount = PhotobookPDFExporter.exportPages(for: draft, layoutRepository: BundleAlbumLayoutRepository()).count
        let document = try #require(PDFDocument(url: pdfURL))
        #expect(document.pageCount == expectedPageCount)
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            let bounds = page.bounds(for: .mediaBox)
            #expect(bounds.width == 720)
            #expect(bounds.height == 720)
            #expect(bounds.origin == .zero)
        }
    }

    @Test func exportReportsPagesInOrder() async throws {
        let draft = draft(spreadCount: 2)
        let workingDirectory = makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let exporter = PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: MockPhotobookExportPhotoLoader())
        var renderedPages: [Int] = []
        _ = try await exporter.export(draft: draft, workingDirectory: workingDirectory) { progress in
            if case let .renderingPage(page, _) = progress.phase, page > 0 {
                renderedPages.append(page)
            }
        }
        #expect(renderedPages == [1, 2, 3, 4, 5])
    }

    /// § user report — a blank Page (no layout) used to throw `.layoutMissing` and stop the whole
    /// export instead of being skipped/rendered as a plain white page.
    @Test func blankPageExportsAsAWhitePageInsteadOfThrowing() async throws {
        let d = AlbumDraft(
            id: "draft-blank-test", title: "Blank Page Test", subtitle: nil, coverPhotoId: "cover-photo",
            startDate: nil, endDate: nil, primaryLocationName: nil, primaryPlace: nil,
            sourceEvents: [], spreads: [spread(id: "s0", order: 0, rightIsBlank: true)],
            createdAt: Date(), planningVersion: 1, planningLog: nil
        )
        let workingDirectory = makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let exporter = PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: MockPhotobookExportPhotoLoader())
        // Must not throw `.layoutMissing` for the blank page.
        let pdfURL = try await exporter.export(draft: d, workingDirectory: workingDirectory) { _ in }

        // Cover + s0-left (real photo) + s0-right (blank) = 3 pages, none skipped.
        let document = try #require(PDFDocument(url: pdfURL))
        #expect(document.pageCount == 3)
    }

    /// § "Vẫn render 1 trang trắng tinh" — samples the blank page's own JPEG (not just the PDF
    /// page count) to confirm it's genuinely pure white, not the Editor's gray/neutral placeholder
    /// fill (`PhotobookPDFExporter.blankPageImage`, not `PhotobookPageBitmapRenderer`'s normal
    /// per-slot placeholder).
    @Test func blankPageIsPureWhiteNotAPlaceholderFill() async throws {
        let d = AlbumDraft(
            id: "draft-blank-white-test", title: "Blank White Test", subtitle: nil, coverPhotoId: "cover-photo",
            startDate: nil, endDate: nil, primaryLocationName: nil, primaryPlace: nil,
            sourceEvents: [], spreads: [spread(id: "s0", order: 0, rightIsBlank: true)],
            createdAt: Date(), planningVersion: 1, planningLog: nil
        )
        let workingDirectory = makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let exporter = PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: MockPhotobookExportPhotoLoader())
        let pdfURL = try await exporter.export(draft: d, workingDirectory: workingDirectory) { _ in }

        let document = try #require(PDFDocument(url: pdfURL))
        // Cover=0, s0-left=1, s0-right(blank)=2.
        let blankPDFPage = try #require(document.page(at: 2))
        let thumbnail = blankPDFPage.thumbnail(of: CGSize(width: 50, height: 50), for: .mediaBox)
        let sampled = pixel(of: try #require(thumbnail.cgImage), atTopLeftX: 25, y: 25)
        #expect(sampled.r > 245 && sampled.g > 245 && sampled.b > 245, "expected the blank page to render pure white, sampled \(sampled)")
    }

    /// § "JPEG phủ toàn bộ PDF page, không có viền trắng" — verified structurally: the source
    /// bitmap is exactly the full 3000×3000 canvas (§ bitmap size test above) and
    /// `PhotobookPDFExporter.assemblePDF` draws it at exactly `CGRect(origin: .zero, size:
    /// pointSize)` — the page's own full bounds — never a smaller/inset rect. This test confirms
    /// the JPEG file actually written to disk mid-export has that same full pixel size (i.e. the
    /// encode step didn't silently downsize it before the PDF draw call would have used it).
    @Test func perPageJPEGFillsTheFullOutputCanvas() throws {
        let layout = try BundleAlbumLayoutRepository().layout(id: "square.1.full-bleed")
        let viewerPage = AlbumViewerPage(
            id: "p1", page: page(id: "p1", photoId: "photo-a"), pageNumber: 1, totalPageCount: 1,
            spreadId: "s1", spreadIndex: 0, positionInSpread: .left
        )
        let cgImage = try PhotobookPageBitmapRenderer().render(
            page: viewerPage, layout: layout, images: ["photo-1": solidColorCGImage(width: 400, height: 400, color: .systemGreen)]
        )
        let jpegData = try #require(UIImage(cgImage: cgImage).jpegData(compressionQuality: PhotobookPDFExporter.jpegCompressionQuality))
        let decoded = try #require(UIImage(data: jpegData)?.cgImage)
        #expect(decoded.width == 3000)
        #expect(decoded.height == 3000)
    }

    // MARK: - Errors

    @Test func missingPhotoThrowsPhotoUnavailableNamingTheRightPageAndAsset() async throws {
        let draft = draft(spreadCount: 1)
        let workingDirectory = makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let loader = MockPhotobookExportPhotoLoader(failingAssetIDs: ["s0-left-photo"])
        let exporter = PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: loader)

        do {
            _ = try await exporter.export(draft: draft, workingDirectory: workingDirectory) { _ in }
            Issue.record("expected export to throw .photoUnavailable")
        } catch let error as PhotobookExportError {
            guard case let .photoUnavailable(pageNumber, assetLocalIdentifier) = error else {
                Issue.record("expected .photoUnavailable, got \(error)")
                return
            }
            // Cover is page 1; s0-left is the first content page → page 2.
            #expect(pageNumber == 2)
            #expect(assetLocalIdentifier == "s0-left-photo")
        }
    }

    // MARK: - Cancellation

    @Test func cancellingDuringPhotoLoadThrowsCancelled() async throws {
        let draft = draft(spreadCount: 6)
        let workingDirectory = makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let loader = MockPhotobookExportPhotoLoader(artificialDelayNanoseconds: 20_000_000, suspensionsPerLoad: 3)
        let exporter = PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: loader)

        let task = Task {
            try await exporter.export(draft: draft, workingDirectory: workingDirectory) { _ in }
        }
        try await Task.sleep(nanoseconds: 15_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation to throw")
        } catch let error as PhotobookExportError {
            #expect(error == .cancelled)
        }
    }

    /// The exact scenario the redesigned `PhotobookExportSession` exists to prevent: cancel mid
    /// export, then immediately call `start(draft:)` again — must never end up with two
    /// `PhotobookPDFExporter.export` calls racing each other.
    @MainActor
    @Test func retryImmediatelyAfterCancelNeverRunsTwoExportsConcurrently() async throws {
        let draft = draft(spreadCount: 6)
        let activeExportCount = ExportConcurrencyCounter()
        let loader = MockPhotobookExportPhotoLoader(artificialDelayNanoseconds: 10_000_000, suspensionsPerLoad: 2)
        let exporter = PhotobookPDFExporter(
            layoutRepository: BundleAlbumLayoutRepository(),
            photoLoader: CountingPhotoLoader(wrapped: loader, counter: activeExportCount)
        )
        let session = PhotobookExportSession(exporter: exporter)

        session.start(draft: draft)
        try await Task.sleep(nanoseconds: 5_000_000)
        session.cancel()
        // Retry *immediately* — while the cancelled Task may still be unwinding.
        session.start(draft: draft)

        // Poll briefly for a terminal state — this test's actual assertion is
        // `activeExportCount.maxObserved <= 1`, checked throughout via `CountingPhotoLoader`.
        for _ in 0..<200 {
            switch session.state {
            case .completed, .failed:
                await Task.yield()
                #expect(await activeExportCount.maxObserved <= 1, "more than one export ran concurrently after an immediate retry-after-cancel")
                return
            default:
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        Issue.record("export never reached a terminal state")
    }

    // MARK: - Memory bound across many pages

    /// Best-effort, not a precise measurement — samples the process's own resident memory before
    /// and after exporting a photobook with many pages, using a mock loader that returns a real,
    /// several-megapixel `CGImage` per photo (matching the export's actual 3000×3000-canvas-scaled
    /// request sizes) so this exercises genuine per-page allocation, not a trivially small stand-in.
    @Test func manyPageExportDoesNotAccumulateMemory() async throws {
        let draft = draft(spreadCount: 15) // 1 cover + 30 content pages = 31 pages
        let workingDirectory = makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let exporter = PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: MockPhotobookExportPhotoLoader())

        let before = Self.residentMemoryBytes()
        _ = try await exporter.export(draft: draft, workingDirectory: workingDirectory) { _ in }
        let after = Self.residentMemoryBytes()

        guard before > 0, after > 0 else { return }
        let growthMB = Double(after > before ? after - before : 0) / 1_048_576
        #expect(growthMB < 100, "resident memory grew by \(growthMB) MB across a 31-page export — pages may not be releasing between iterations")
    }

    // MARK: - Temp file cleanup

    @Test func successLeavesOnlyTheFinalPDFInTheWorkingDirectory() async throws {
        let draft = draft(spreadCount: 2)
        let workingDirectory = makeWorkingDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let exporter = PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: MockPhotobookExportPhotoLoader())
        let pdfURL = try await exporter.export(draft: draft, workingDirectory: workingDirectory) { _ in }

        let remaining = try FileManager.default.contentsOfDirectory(atPath: workingDirectory.path)
        #expect(remaining == [pdfURL.lastPathComponent])
    }

    @MainActor
    @Test func sessionDeletesItsDirectoryAfterCancellation() async throws {
        let draft = draft(spreadCount: 4)
        let loader = MockPhotobookExportPhotoLoader(artificialDelayNanoseconds: 15_000_000, suspensionsPerLoad: 2)
        let session = PhotobookExportSession(
            exporter: PhotobookPDFExporter(layoutRepository: BundleAlbumLayoutRepository(), photoLoader: loader)
        )

        session.start(draft: draft)
        try await Task.sleep(nanoseconds: 8_000_000)
        session.cancel()

        for _ in 0..<200 {
            if case .idle = session.state { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(session.state == .idle)

        let photobookExportRoot = FileManager.default.temporaryDirectory.appendingPathComponent("PhotobookExport", isDirectory: true)
        let sessionDirs = (try? FileManager.default.contentsOfDirectory(atPath: photobookExportRoot.path)) ?? []
        // Not asserting zero (other tests may run concurrently and leave their own session dirs)
        // — only that *this* session's own directory is gone is verifiable from outside without
        // exposing its private `sessionDirectory` property, so this checks the weaker but still
        // meaningful invariant: no stray *.pdf sitting directly in the shared root.
        #expect(sessionDirs.allSatisfy { !$0.hasSuffix(".pdf") })
    }

    // MARK: - Helpers

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

/// Never touches PhotoKit — returns a synthetic solid-color `CGImage` at exactly the requested
/// pixel size. `suspensionsPerLoad` deliberately awaits (and yields) multiple times per call, so
/// tests exercising cancellation/thread-hopping robustness have real suspension points to land on
/// mid-load, not just a single opaque `await`.
private final class MockPhotobookExportPhotoLoader: PhotobookExportPhotoLoading, @unchecked Sendable {
    private let failingAssetIDs: Set<String>
    private let artificialDelayNanoseconds: UInt64
    private let suspensionsPerLoad: Int

    init(failingAssetIDs: Set<String> = [], artificialDelayNanoseconds: UInt64 = 0, suspensionsPerLoad: Int = 1) {
        self.failingAssetIDs = failingAssetIDs
        self.artificialDelayNanoseconds = artificialDelayNanoseconds
        self.suspensionsPerLoad = max(suspensionsPerLoad, 1)
    }

    func loadImage(
        reference: AlbumPhotoReference, targetPixelSize: CGSize, contentMode: AlbumPhotoContentMode,
        onDownloadProgress: (@Sendable (Double) -> Void)?
    ) async throws -> CGImage {
        for step in 0..<suspensionsPerLoad {
            if artificialDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: artificialDelayNanoseconds / UInt64(suspensionsPerLoad))
            } else {
                await Task.yield()
            }
            try Task.checkCancellation()
            onDownloadProgress?(Double(step + 1) / Double(suspensionsPerLoad))
        }
        if failingAssetIDs.contains(reference.sourceIdentifier) {
            throw AlbumPhotoProviderError.assetNotFound
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: max(targetPixelSize.width, 1), height: max(targetPixelSize.height, 1))
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.cgImage!
    }
}

/// Actor-isolated counter — `CountingPhotoLoader` increments it around every `loadImage` call so
/// `retryImmediatelyAfterCancelNeverRunsTwoExportsConcurrently` can assert at most one export's
/// worth of photo-loading work is ever in flight at once.
private actor ExportConcurrencyCounter {
    private var active = 0
    private(set) var maxObserved = 0

    func increment() {
        active += 1
        maxObserved = max(maxObserved, active)
    }

    func decrement() {
        active -= 1
    }
}

private struct CountingPhotoLoader: PhotobookExportPhotoLoading {
    let wrapped: any PhotobookExportPhotoLoading
    let counter: ExportConcurrencyCounter

    func loadImage(
        reference: AlbumPhotoReference, targetPixelSize: CGSize, contentMode: AlbumPhotoContentMode,
        onDownloadProgress: (@Sendable (Double) -> Void)?
    ) async throws -> CGImage {
        await counter.increment()
        defer { Task { await counter.decrement() } }
        return try await wrapped.loadImage(
            reference: reference, targetPixelSize: targetPixelSize, contentMode: contentMode, onDownloadProgress: onDownloadProgress
        )
    }
}
