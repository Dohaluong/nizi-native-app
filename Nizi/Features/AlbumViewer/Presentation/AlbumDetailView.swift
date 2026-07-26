//
//  AlbumDetailView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI
import Photos

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
    /// library. Returns `false` on `cannotRemoveLastPhotoOnPage` (surfaced by the preview as its
    /// own alert) or any other failure (logged, not surfaced — matches `deleteAlbum()`'s own
    /// quiet-log convention below for infrequent, hard-to-explain-in-one-line errors).
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
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
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
                .background(.ultraThinMaterial, in: Circle())
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
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
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
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            pagerContent(item)
        }
    }

    @ViewBuilder
    private func pagerContent(_ item: AlbumViewerItem) -> some View {
        switch item {
        case let .cover(configuration):
            AlbumCoverView(configuration: configuration)
        case let .page(viewerPage):
            AlbumPageCardView(viewerPage: viewerPage, layoutRepository: layoutRepository) { assignment in
                openPhotoPreview(for: assignment, on: viewerPage)
            }
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
