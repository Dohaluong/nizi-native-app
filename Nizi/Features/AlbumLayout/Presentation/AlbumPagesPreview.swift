//
//  AlbumPagesPreview.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// A hero cover plus a horizontally-paged run of Album pages, each one rendered from a *real*
/// layout pulled from `AlbumLayoutRepository` via `AlbumPageRenderer` — never a hand-built
/// per-photo-count SwiftUI layout (§ Album Pages Preview). This is a standalone demo/acceptance
/// screen for the layout engine itself; it doesn't touch the existing, already-approved
/// `AlbumDetailDesignPreview` hero or its page carousel (§ Development constraints — "không thay
/// đổi hero cover đã được người dùng xác nhận là ổn").
struct AlbumPagesPreview: View {
    private let layoutSelector: AlbumLayoutSelecting
    @State private var selectedPage = 0

    /// One entry per demo page — just a photo count, since the real layout for each is resolved
    /// from the repository at render time, not hardcoded here.
    private let pagePhotoCounts = [1, 2, 3, 4, 2, 3]

    init(repository: AlbumLayoutRepository = BundleAlbumLayoutRepository()) {
        layoutSelector = DefaultAlbumLayoutSelector(repository: repository)
    }

    private var pages: [(layout: AlbumPageLayout, error: Error?)] {
        pagePhotoCounts.map { count in
            do {
                let layout = try layoutSelector.defaultLayout(photoCount: count, format: .square)
                return (layout, nil)
            } catch {
                return (AlbumPagesPreview.placeholderLayout(photoCount: count), error)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroCover
                pagesSection
            }
            // Container (this ScrollView's own width) determines page size — the pages below
            // never grow past it, regardless of what the placeholder photos report.
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Hero

    private var heroCover: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.blue.opacity(0.9), Color.indigo.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.white.opacity(0.22))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text("album.layout.pages_preview.title")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("album.layout.pages_preview.subtitle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(22)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Pages

    private var pagesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageInfo
                .padding(.horizontal, 20)

            pageCarousel

            pageIndicator
        }
        .padding(.top, 24)
        .padding(.bottom, 40)
    }

    private var pageInfo: some View {
        let currentPage = pages[safe: selectedPage]
        return VStack(alignment: .leading, spacing: 2) {
            Text(
                localizedString(
                    "album.layout.page",
                    defaultValue: "Page \(selectedPage + 1) / \(pages.count)"
                )
            )
            .font(.subheadline.bold())

            if let currentPage {
                Text(currentPage.layout.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        // Left-aligned explicitly — a horizontally-paging TabView's own pages can otherwise read
        // as drifting since each page's content is centered by default (§ "Không lệch trái").
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageCarousel: some View {
        TabView(selection: $selectedPage) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                AlbumPageRenderer(
                    layout: page.layout,
                    assignments: numberedAssignments(for: page.layout),
                    photoProvider: NumberedPlaceholderPhotoProvider(),
                    showsDebugSlotIds: false
                )
                // The page's own frame is what fixes its size — the renderer (and the photos
                // inside it) never push this wider/taller than the container proposes
                // (§ "Kích thước trang được xác định bởi container").
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 20)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // A fixed height here (not `.aspectRatio` alone) is what keeps the whole carousel from
        // overflowing the viewport regardless of what any individual page reports
        // (§ "Không để nội dung vượt viewport").
        .frame(height: 420)
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(selectedPage == index ? Color.primary : Color.secondary.opacity(0.25))
                    .frame(width: selectedPage == index ? 20 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: selectedPage)
    }

    /// Only reached if the repository/library itself failed to load — the demo page list still
    /// needs *some* layout to render so the screen shows an inline error state instead of
    /// crashing (§ "Renderer không được crash khi thiếu assignment" extends in spirit to a
    /// missing layout here too).
    private static func placeholderLayout(photoCount: Int) -> AlbumPageLayout {
        AlbumPageLayout(
            id: "unavailable",
            name: "Unavailable",
            nameKey: "album.layout.unavailable",
            photoCount: photoCount,
            supportedFormats: [.square],
            referenceCanvas: AlbumReferenceCanvas(width: 1000, height: 1000),
            background: AlbumLayoutBackground(type: .solid, value: "#FFFFFF"),
            slots: (0..<photoCount).map { index in
                AlbumLayoutSlot(
                    id: "photo-\(index + 1)",
                    order: index,
                    role: index == 0 ? .hero : .supporting,
                    preferredOrientation: .square,
                    frame: AlbumLayoutFrame(x: 0, y: 0, width: 1000, height: 1000),
                    contentMode: .fill,
                    cornerRadius: 0
                )
            }
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("Album Pages — Layout Engine") {
    AlbumPagesPreview()
}
