//
//  AlbumDetailView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI
import Photos
import UIKit

/// Production Album Detail — a direct port of `AlbumDetailDesignPreview.swift`'s design (same
/// colors, backgrounds, paddings, fonts throughout) wired to real data: a real cover photo, and
/// every Page (Cover first, then Page 1, 2, 3…) stacked in one continuous vertical scroll below
/// it — never a horizontal-swipe carousel. Each Page gets its own pencil to open the single-page
/// Viewer in edit mode for that Page specifically. There is no separate "Open Album" screen to
/// browse Pages. See docs/specs/SPEC-REAL-ALBUM.md § 12 and docs/specs/ADDENDUM-001.md § 21.
struct AlbumDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: AlbumDraft
    let onUpdate: (AlbumDraft) async -> Void
    let onDelete: () async -> Void

    @State private var editTarget: EditTarget?
    @State private var photoPreviewTarget: PhotoPreviewTarget?
    @State private var isEditingInfo = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var pagesScrollOffset: CGFloat = 0

    private static let backToTopThreshold: CGFloat = 700
    private static let backSwipeEdgeWidth: CGFloat = 28
    private static let backSwipeDistance: CGFloat = 80

    private let itemBuilder: AlbumViewerItemBuilding = DefaultAlbumViewerItemBuilder()
    private let layoutRepository: AlbumLayoutRepository = BundleAlbumLayoutRepository()
    private let editActionApplier: AlbumEditActionApplying = DefaultAlbumEditActionApplying()

    init(draft: AlbumDraft, onUpdate: @escaping (AlbumDraft) async -> Void = { _ in }, onDelete: @escaping () async -> Void = {}) {
        _draft = State(initialValue: draft)
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    private struct EditTarget: Identifiable {
        let itemId: String
        var id: String { itemId }
    }

    /// `photos`/`startIndex` are scoped to a single Page — the zoomed preview only ever pans
    /// across that Page's own photos, never the whole Album.
    private struct PhotoPreviewTarget: Identifiable {
        let id = UUID()
        let photos: [AlbumPhotoAssignment]
        let pageId: String
        let startIndex: Int
    }

    // MARK: - Data

    /// Cover first, then every Page — the single source of truth for the vertical Pages scroll.
    private var pagerItems: [AlbumViewerItem] {
        itemBuilder.makeItems(from: draft)
    }

    private var coverConfiguration: AlbumCoverConfiguration {
        guard case let .cover(configuration) = pagerItems.first else {
            return AlbumCoverConfiguration(photo: draft.coverPhotoReference, title: draft.title, subtitle: nil, dateText: nil, placeText: nil, styleId: AlbumCoverConfiguration.classicStyleId)
        }
        return configuration
    }

    /// "PLACE · YEAR", matching the design's eyebrow (e.g. "SYDNEY · 2026").
    private var heroEyebrow: String {
        let year = Calendar.current.component(.year, from: draft.startDate ?? draft.createdAt)
        guard let place = coverConfiguration.placeText, !place.isEmpty else { return "\(year)" }
        return "\(place.uppercased()) · \(year)"
    }

    /// Stands in for the design's narrative "introduction" paragraph — there's no real story
    /// text to show, so this is the real place/photo/spread summary instead, in the same slot.
    private var overviewText: String {
        let photos = localizedString("album.photosCount", defaultValue: "\(draft.totalPhotoCount) photos")
        let spreads = localizedString("album.spreadsCount", defaultValue: "\(draft.spreads.count) spreads")
        if let place = coverConfiguration.placeText, !place.isEmpty {
            return "\(place) · \(photos) · \(spreads)"
        }
        return "\(photos) · \(spreads)"
    }

    /// Every photo across every Page of this Album, in `AlbumDraft` order — what `EditorContext.
    /// photoIds` needs for "apply style to whole Album" (§ 11.4), as opposed to `orderedAssignments`
    /// below, which is deliberately scoped to a single Page.
    private var allAlbumPhotoIds: [String] {
        draft.spreads
            .flatMap { [$0.leftPage, $0.rightPage] }
            .flatMap(\.assignments)
            .map(\.photo.sourceIdentifier)
    }

    private func orderedAssignments(for viewerPage: AlbumViewerPage) -> [AlbumPhotoAssignment] {
        guard let layout = try? layoutRepository.layout(id: viewerPage.page.layoutId) else {
            return viewerPage.page.assignments
        }
        let assignmentsBySlotId = Dictionary(uniqueKeysWithValues: viewerPage.page.assignments.map { ($0.slotId, $0) })
        return layout.slots.sorted { $0.order < $1.order }.compactMap { assignmentsBySlotId[$0.id] }
    }

    /// Scoped to `viewerPage`'s own photos only (never the whole Album) — resolves the tapped
    /// photo's position by matching `slotId` (unique within one Page by construction) rather than
    /// `assignment.id`, since some already-persisted Drafts have assignment ids that collide
    /// across Pages (pre-dating the id-generation fix in `AlbumPhotoSlotAssigner`).
    private func openPhotoPreview(for assignment: AlbumPhotoAssignment, on viewerPage: AlbumViewerPage) {
        let pagePhotos = orderedAssignments(for: viewerPage)
        guard let localIndex = pagePhotos.firstIndex(where: { $0.slotId == assignment.slotId }) else { return }
        photoPreviewTarget = PhotoPreviewTarget(photos: pagePhotos, pageId: viewerPage.page.id, startIndex: localIndex)
    }

    /// "Hide from Album" (from `AlbumPhotoPreviewView`'s "..." menu) — removes just this one
    /// photo's assignment from its Page via the same `AlbumEditAction.removePhoto` the full Page
    /// editor's own "Remove Photo" tool uses (`AlbumPageViewer.swift`), never touching the Photos
    /// library. Removing a Page's last photo now succeeds (it becomes a blank placeholder, § user
    /// request "xoá hết ảnh"), so `false` here is only a genuine failure — surfaced by the preview
    /// as its own generic alert, logged here too (matches `deleteAlbum()`'s own quiet-log
    /// convention below for infrequent, hard-to-explain-in-one-line errors).
    private func hidePhoto(pageId: String, slotId: String) async -> Bool {
        do {
            let updated = try await editActionApplier.apply(.removePhoto(pageId: pageId, slotId: slotId), to: draft)
            draft = updated
            await onUpdate(updated)
            return true
        } catch {
            NiziLogger.discovery.error("album_hide_photo_failed error=\(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Deletes only the persisted Draft row — never touches the Photos Library.
    private func deleteAlbum() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let store = SwiftDataAlbumDraftStore(modelContainer: modelContext.container)
            try await store.deleteDraft(id: draft.id)
            await onDelete()
            dismiss()
        } catch {
            NiziLogger.discovery.error("album_delete_failed")
        }
    }

    // MARK: - Body

    var body: some View {
        // `GeometryReader` (not `UIScreen.main.bounds`) is the source of truth for "how wide is
        // this view actually allowed to be" — it reflects the real window/scene size in every
        // context (iPad Split View, Slide Over, rotation), where `UIScreen.main.bounds` only
        // reflects the full physical screen and would be wrong the moment this app's window is
        // narrower than that (this project targets both iPhone and iPad, and supports landscape
        // on both — see `TARGETED_DEVICE_FAMILY`/`INFOPLIST_KEY_UISupportedInterfaceOrientations*`
        // in the project settings).
        GeometryReader { proxy in
            // A UIKit control is used for Back to Top: it receives the touch independently of
            // SwiftUI's `ScrollView` gesture system and directly cancels any current deceleration
            // before changing the offset. A SwiftUI Button in this layer could still have its
            // first tap consumed solely to stop the scroll's momentum.
            ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        VStack(spacing: 0) {
                            heroCover
                            albumIntroduction
                            albumPagesSection(width: proxy.size.width)
                        }
                        // Hard-clamped to the real available width. `ScrollView` only constrains its
                        // content on the scrolling (vertical) axis — on the cross (horizontal) axis it
                        // lets content be as wide as content *wants* to be. Some Album's "Story" text (a
                        // long place name + counts, via `.fixedSize(horizontal: false, vertical: true)`)
                        // could report an ideal width wider than the screen instead of wrapping, and once
                        // any one descendant does that, the whole column — Hero, the Pages carousel,
                        // everything — inherits that wider width, which is what "images/text flush
                        // against the screen edges" actually was: the whole page was rendering wider than
                        // the device, not that padding stopped working. An absolute `.frame(width:)` here
                        // makes that structurally impossible — nothing below this point can ever push the
                        // page wider than the real available width again.
                        .frame(width: proxy.size.width)
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y
                    } action: { _, newValue in
                        pagesScrollOffset = newValue
                    }

                    // § user request — "Tôi còn cần một nút tròn mũi tên đi lên. Khi qua trang thứ
                    // 2 sẽ hiện nút để Back to Top nhanh hơn": there's no cheap way to know "exactly
                    // past Page 2's own frame" from here (Pages are `LazyVStack`, so most of them
                    // are never even measured until they scroll into view) — `backToTopThreshold`
                    // is a fixed scroll-distance stand-in instead (roughly hero + intro + one full
                    // Page card), the same "good enough" approximation most apps' own back-to-top
                    // affordances use rather than tracking every row's exact on-screen position.
                    if pagesScrollOffset > Self.backToTopThreshold {
                        backToTopButton()
                            .zIndex(1)
                    }
            }
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
        // The Album can be either a pushed NavigationStack destination or the root of a
        // full-screen cover. `dismiss()` is the correct back operation in both cases, whereas
        // UIKit's built-in interactive-pop gesture only exists in the first case. Keeping this
        // gesture simultaneous means the vertical Album scroll continues to behave normally.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let horizontalDistance = value.translation.width
                    let verticalDistance = value.translation.height
                    guard
                        value.startLocation.x <= Self.backSwipeEdgeWidth,
                        horizontalDistance >= Self.backSwipeDistance,
                        abs(horizontalDistance) > abs(verticalDistance)
                    else { return }
                    dismiss()
                },
            including: .all
        )
        .fullScreenCover(item: $editTarget) { target in
            AlbumPageViewer(draft: draft, startInEditMode: true, initialItemId: target.itemId) { updated in
                draft = updated
                await onUpdate(updated)
            }
            .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
        }
        .fullScreenCover(item: $photoPreviewTarget) { target in
            AlbumPhotoPreviewView(
                photos: target.photos, albumId: draft.id, allAlbumPhotoIds: allAlbumPhotoIds, pageId: target.pageId,
                startIndex: target.startIndex,
                onPhotoReplaced: { oldPhotoId, newPhoto in
                    let updated = editActionApplier.replacePhoto(oldPhotoId: oldPhotoId, with: newPhoto, in: draft)
                    draft = updated
                    Task { await onUpdate(updated) }
                },
                onHidePhoto: { pageId, slotId in
                    await hidePhoto(pageId: pageId, slotId: slotId)
                }
            ) {
                photoPreviewTarget = nil
            }
            .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
        }
        .sheet(isPresented: $isEditingInfo) {
            AlbumInfoEditSheet(draft: draft) { updated in
                draft = updated
                await onUpdate(updated)
            }
            .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
        }
        .confirmationDialog(
            "album.edit.info.delete_confirm_title", isPresented: $showDeleteConfirmation, titleVisibility: .visible
        ) {
            Button("album.deleteAlbum", role: .destructive) { Task { await deleteAlbum() } }
            Button("common.action.cancel", role: .cancel) {}
        } message: {
            Text("album.photosRemainInLibrary")
        }
    }

    // MARK: - Hero

    private var heroCover: some View {
        ZStack {
            heroImage
            heroGradient
            heroNavigation
            heroContent
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var heroImage: some View {
        AlbumPhotoView(reference: draft.coverPhotoReference, crop: .centered, contentMode: .fill, targetSize: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var heroGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.15), location: 0),
                .init(color: .clear, location: 0.32),
                .init(color: .black.opacity(0.08), location: 0.52),
                .init(color: .black.opacity(0.82), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var heroNavigation: some View {
        VStack {
            HStack {
                heroButton(systemImage: "chevron.left") { dismiss() }
                Spacer()
                albumOptionsMenu
            }
            .padding(.horizontal, 18)
            .padding(.top, 54)
            Spacer()
        }
    }

    private var albumOptionsMenu: some View {
        Menu {
            Button {
                isEditingInfo = true
            } label: {
                Label("album.editAlbum", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("album.deleteAlbum", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .disabled(isDeleting)
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Text(heroEyebrow)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.bottom, 10)

            Text(draft.title)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.bottom, 7)

            if let subtitle = draft.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .padding(.bottom, 16)
            }

            if let dateText = coverConfiguration.dateText {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                    Text(dateText)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private func heroButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func backToTopButton() -> some View {
        AlbumBackToTopControl()
            .frame(width: 46, height: 46)
        .padding(.trailing, 20)
        .padding(.bottom, 30)
        .transition(.opacity.combined(with: .scale(scale: 0.7)))
    }

    // MARK: - Introduction

    private var albumIntroduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("album.detail.story_section.title")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            Text(overviewText)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            if !draft.sourceEvents.isEmpty {
                sourceEventsList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 30)
        .background(Color(.systemBackground))
    }

    private var sourceEventsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("album.detail.source_events_title")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            // § 17 — only Events with a real title, never a raw Event ID.
            ForEach(draft.sourceEvents.filter { ($0.title?.isEmpty == false) }, id: \.id) { event in
                Text(event.title ?? "")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Album Pages

    private func albumPagesSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            pageSectionHeader
            pagesColumn(width: width)
            addPageButton
                .padding(.horizontal, 20)
        }
        .padding(.top, 26)
        .padding(.bottom, 48)
        // Belt-and-suspenders alongside the hard clamp on `pagesColumn` below — a `VStack`
        // reports its own width as whatever its widest child needs, then *proposes that same
        // width back down* to every child (including `pageSectionHeader`, which is why its own
        // "Album"/page-count text was also seen sitting at the wrong width even though that text
        // itself is short). Clamping here too means nothing in this section can drift again even
        // if some future child does the same thing `TabView` used to.
        .frame(width: width, alignment: .leading)
    }

    // Just the section title/count — there is no single "current Page" anymore now that every
    // Page sits in one continuous vertical scroll (§ layout request), so the old "edit whichever
    // Page is currently shown" pencil moved to each Page's own number row instead (see
    // `pagerItemView`).
    private var pageSectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("album.detail.pages_section.title")
                .font(.system(size: 26, weight: .bold))
            Text(localizedString("album.detail.page_count", defaultValue: "\(pagerItems.count) pages"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    /// Cover, then every Page, stacked vertically in one continuous scroll — the user swipes up
    /// through Cover → Page 1 → Page 2 → … seamlessly, the same gesture that scrolls the rest of
    /// this screen, instead of a horizontal-swipe carousel. `LazyVStack`, not a plain `VStack`, is
    /// what makes "generate a Page only once it's about to be scrolled into view" real: each
    /// Page's `AlbumPageCardView` (its photo loads included) is only actually built once it's near
    /// the visible viewport, not all `pagerItems.count` of them the moment this Album opens — the
    /// memory win the vertical-scroll request specifically asked for.
    private func pagesColumn(width: CGFloat) -> some View {
        LazyVStack(alignment: .leading, spacing: 36) {
            ForEach(pagerItems) { item in
                pagerItemView(item)
                    .padding(.horizontal, 20)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    /// § user request — "Ngoài Album ở trang cuối cùng có 1 nút: Thêm trang. Khi thêm sẽ tạo ra 1
    /// trang trắng": appends one blank Page and persists right away — same direct-commit posture
    /// `hidePhoto`/photo replace above already take, no separate edit session involved (there's
    /// nothing to review/undo before saving; the new Page starts out empty either way).
    private var addPageButton: some View {
        Button {
            Task { await addBlankPage() }
        } label: {
            Label("album.addPage", systemImage: "plus.square.dashed")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.gray)
    }

    private func addBlankPage() async {
        do {
            let updated = try await editActionApplier.apply(.addBlankPage, to: draft)
            draft = updated
            await onUpdate(updated)
        } catch {
            NiziLogger.discovery.error("album_add_blank_page_failed error=\(String(describing: error), privacy: .public)")
        }
    }

    // The page number and its own edit pencil sit *above* that Page's content, not overlaid on
    // top of it — same item, same VStack, so they scroll together as one unit.
    @ViewBuilder
    private func pagerItemView(_ item: AlbumViewerItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pageNumberText(for: item))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editTarget = EditTarget(itemId: item.id)
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.gray)
                }
                .buttonStyle(.plain)
            }
            pagerContent(item)
        }
    }

    // § user request — "trang bìa sẽ có cấu trúc như trang ruột ... Layout (square.1.cover) là
    // ảnh tràn viền nhưng chi tiết bìa lại có viền? điều này không đúng": the old `AlbumCoverView`
    // drew its own bespoke chrome (an 18pt-radius rounded rect + a visible stroke overlay +
    // shadow) regardless of the layout's own `cornerRadius` (0 — full-bleed) — that mismatch is
    // exactly the "viền" (border) the Cover shouldn't have here. Rendering it through the same
    // `AlbumPageCardView` every content Page already uses (via `AlbumCoverPageBuilder`, shared
    // with `AlbumPageViewer`) makes it pick up the real layout's own corner radius/gradient
    // instead, and look identical to every other Page's card styling. `AlbumCoverConfiguration`
    // itself is unchanged and still used just above for `heroEyebrow`/`overviewText`.
    @ViewBuilder
    private func pagerContent(_ item: AlbumViewerItem) -> some View {
        switch item {
        case .cover:
            let coverViewerPage = AlbumCoverPageBuilder.makeViewerPage(from: draft, layoutRepository: layoutRepository)
            AlbumPageCardView(viewerPage: coverViewerPage, layoutRepository: layoutRepository) { assignment in
                openPhotoPreview(for: assignment, on: coverViewerPage)
            }
        case let .page(viewerPage):
            AlbumPageCardView(
                viewerPage: viewerPage, layoutRepository: layoutRepository,
                onTapPhoto: { assignment in openPhotoPreview(for: assignment, on: viewerPage) },
                // § user request — "Thêm trang ... Click vào có thể thêm ảnh sau": this read-only
                // screen has no picker sheet of its own, so tapping a blank Page here just opens
                // the full editor at that Page (same as its own pencil/grid button below) — adding
                // the actual photo happens inside `AlbumPageViewer`, which does have one.
                onTapBlankPage: { editTarget = EditTarget(itemId: viewerPage.id) }
            )
        }
    }

    private func pageNumberText(for item: AlbumViewerItem) -> String {
        switch item {
        case .cover:
            return String(localized: "album.viewer.cover_page_label")
        case let .page(page):
            return localizedString("album.viewer.page_number_label", defaultValue: "Page \(page.pageNumber)")
        }
    }
}

/// A direct UIKit control avoids the `UIScrollView` behavior where the first SwiftUI tap while
/// decelerating only stops momentum. Setting `contentOffset` also explicitly interrupts that
/// momentum, so the same press immediately starts the trip back to the top.
private struct AlbumBackToTopControl: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "arrow.up")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        configuration.cornerStyle = .capsule

        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.accessibilityLabel = String(localized: "album.detail.back_to_top")
        button.addTarget(context.coordinator, action: #selector(Coordinator.scrollToTop), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}

    final class Coordinator: NSObject {
        @objc func scrollToTop(_ sender: UIButton) {
            guard let scrollView = enclosingVerticalScrollView(for: sender) else { return }
            let top = CGPoint(x: -scrollView.adjustedContentInset.left, y: -scrollView.adjustedContentInset.top)
            // An immediate set cancels the active deceleration before the animated trip begins.
            scrollView.setContentOffset(scrollView.contentOffset, animated: false)
            scrollView.setContentOffset(top, animated: true)
        }

        private func enclosingVerticalScrollView(for view: UIView) -> UIScrollView? {
            var root = view
            while let superview = root.superview {
                root = superview
            }

            return descendants(of: root)
                .compactMap { $0 as? UIScrollView }
                .filter { $0.contentSize.height > $0.bounds.height }
                .max { $0.bounds.height < $1.bounds.height }
        }

        private func descendants(of view: UIView) -> [UIView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
    }
}
