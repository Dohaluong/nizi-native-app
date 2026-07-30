//
//  AlbumPageViewer.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Production single-page Album viewer (docs/specs/ADDENDUM-001.md — supersedes SPEC-REAL-ALBUM's
/// two-page Spread Viewer for iPhone). Cover first, then every Page in order, one at a time; the
/// underlying `AlbumDraft` still stores Spreads of exactly two Pages (unchanged by this screen).
///
/// Real photos throughout via `AlbumPageRenderer` + `ProductionAlbumSlotPhotoProvider` +
/// `AlbumPhotoView` — no mock placeholders in this call path.
struct AlbumPageViewer: View {
    let onSave: (AlbumDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AlbumDraft
    @State private var editingSession: AlbumEditingSession?
    @State private var selectedItemId: String?
    @State private var isSaving = false
    @State private var editError: String?

    @State private var changeCoverTarget: Bool = false
    @State private var swapSourcePage: AlbumViewerPage?
    @State private var removePhotoTarget: AlbumViewerPage?
    @State private var removeSpreadConfirmation: AlbumViewerPage?
    @State private var removePhotoBlockedAlert = false
    /// § user request — locks `TabView(.page)`'s own page-swiping out for as long as a
    /// drag-to-swap is actively picked up on the current Page (see `AlbumPagingLockView`).
    @State private var isPhotoDragActive = false

    private let itemBuilder: AlbumViewerItemBuilding = DefaultAlbumViewerItemBuilder()
    private let actionApplier: AlbumEditActionApplying = DefaultAlbumEditActionApplying()
    private let layoutRepository: AlbumLayoutRepository = BundleAlbumLayoutRepository()

    /// `startInEditMode`/`initialItemId` let `AlbumDetailView` open this screen already in edit
    /// mode at a specific Page (tapping a Page in its inline carousel), instead of always landing
    /// on the Cover in view mode first.
    init(draft: AlbumDraft, startInEditMode: Bool = false, initialItemId: String? = nil, onSave: @escaping (AlbumDraft) async -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        _selectedItemId = State(initialValue: initialItemId)
        _editingSession = State(initialValue: startInEditMode ? AlbumEditingSession(draft: draft) : nil)
    }

    private var activeDraft: AlbumDraft { editingSession?.workingDraft ?? draft }
    private var isEditing: Bool { editingSession != nil }
    private var items: [AlbumViewerItem] { itemBuilder.makeItems(from: activeDraft) }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedItemId) {
                ForEach(items) { item in
                    itemView(item)
                        .tag(Optional(item.id))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top) {
                if isEditing {
                    layoutPickerHeader
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isEditing { editToolbar }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("album.cancel") { cancelEditing() }
                    } else {
                        Button("common.action.close") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button("album.save") { Task { await saveEditing() } }
                            .disabled(isSaving)
                    } else {
                        Button("album.edit") { beginEditing() }
                    }
                }
            }
        }
        .onChange(of: activeDraft.spreads) { _, _ in
            if let selectedItemId {
                let resolved = AlbumViewerSelection(itemId: selectedItemId).resolved(against: items)
                self.selectedItemId = resolved?.itemId
            }
        }
        .task {
            if selectedItemId == nil {
                selectedItemId = items.first?.id
            }
        }
        .alert("event.album_creation.failed_title", isPresented: .constant(editError != nil)) {
            Button("common.action.cancel", role: .cancel) { editError = nil }
        } message: {
            Text(editError ?? "")
        }
        .alert("album.edit.remove_last_photo_title", isPresented: $removePhotoBlockedAlert) {
            Button("common.action.cancel", role: .cancel) {}
        } message: {
            Text("album.eachPageNeedsPhoto")
        }
        .confirmationDialog(
            "album.edit.remove_spread_title", isPresented: Binding(get: { removeSpreadConfirmation != nil }, set: { if !$0 { removeSpreadConfirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("album.removeSpread", role: .destructive) {
                if let page = removeSpreadConfirmation { removeSpread(containing: page) }
                removeSpreadConfirmation = nil
            }
            Button("common.action.cancel", role: .cancel) { removeSpreadConfirmation = nil }
        } message: {
            Text("album.photosRemainInLibrary")
        }
        .sheet(isPresented: $changeCoverTarget) {
            AlbumPhotoPickerSheet(draft: activeDraft, title: "album.changeCover") { reference in
                apply(.changeCover(photo: reference))
                changeCoverTarget = false
            }
        }
        .sheet(item: $swapSourcePage) { sourcePage in
            AlbumSwapPhotoSheet(currentPage: sourcePage, draft: activeDraft) { firstAssignmentId, secondAssignmentId in
                apply(.swapPhotos(firstAssignmentId: firstAssignmentId, secondAssignmentId: secondAssignmentId))
                swapSourcePage = nil
            }
        }
        .sheet(item: $removePhotoTarget) { targetPage in
            AlbumRemovePhotoSheet(page: targetPage.page) { slotId in
                apply(.removePhoto(pageId: targetPage.page.id, slotId: slotId))
                removePhotoTarget = nil
            }
        }
    }

    // MARK: - Items

    // § layout request — the page number now sits right below each Page's own content (as part
    // of the same `TabView` item, so it slides along with the Page it belongs to) instead of in a
    // persistent top header; the Cover has no page number, so it renders with nothing below it.
    @ViewBuilder
    private func itemView(_ item: AlbumViewerItem) -> some View {
        switch item {
        case let .cover(configuration):
            AlbumCoverView(configuration: configuration)
        case let .page(viewerPage):
            pageView(viewerPage)
        }
    }

    private func pageView(_ viewerPage: AlbumViewerPage) -> some View {
        VStack(spacing: 6) {
            AlbumPageCardView(
                viewerPage: viewerPage, layoutRepository: layoutRepository,
                // § user request — drag-to-swap only while actively editing; outside edit mode
                // `apply(_:)` would silently no-op anyway (no `editingSession`), which would
                // leave the ripple's "new photo" reveal showing the same old photo underneath.
                onSwapPhotos: isEditing
                    ? { from, to in apply(.swapPhotos(firstAssignmentId: from.id, secondAssignmentId: to.id)) }
                    : nil,
                onDragActiveChanged: { isPhotoDragActive = $0 }
            )
            Text(localizedString("album.viewer.page_indicator", defaultValue: "Page \(viewerPage.pageNumber) / \(viewerPage.totalPageCount)"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        // Must be a genuine descendant of this Page's own `TabView` item (see
        // `AlbumPagingLockView`'s own doc comment) so walking `superview` from it resolves to
        // *this* Page's own `UIPageViewController`-backed `UIScrollView`, not some unrelated one.
        .background(AlbumPagingLockView(isLocked: isPhotoDragActive))
    }

    // MARK: - Edit mode

    private var currentViewerPage: AlbumViewerPage? {
        guard case let .page(page) = items.first(where: { $0.id == selectedItemId }) else { return nil }
        return page
    }

    /// § layout request — replaces the old "Change Layout" sheet with an always-visible picker at
    /// the top of the screen: one horizontal row (free to run wider than the screen — pan to see
    /// the rest) of every layout that matches the *current* Page's own photo count (never a
    /// mismatched count — same filter `AlbumLayoutPickerSheet` used to apply), re-filtering
    /// automatically as `currentViewerPage` changes while swiping between Pages. Tapping a swatch
    /// applies it immediately, no confirmation step, and re-centers the row on it. Empty (no
    /// picker at all) while the Cover is showing, since a Cover has no interchangeable Page layout.
    private static let layoutSwatchSize: CGFloat = 64
    private static let layoutPickerVerticalPadding: CGFloat = 12
    /// Explicit, computed height — a `ScrollView` with no bounded height left `.safeAreaInset` to
    /// size this however it liked (observed: it claimed nearly the whole screen, pushing the
    /// actual Page content out). This supplies exactly the row's own height (+ the padding around
    /// it) instead of leaving it ambiguous.
    private static var layoutPickerHeight: CGFloat {
        layoutSwatchSize + layoutPickerVerticalPadding * 2
    }

    @ViewBuilder
    private var layoutPickerHeader: some View {
        if let viewerPage = currentViewerPage {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(candidateLayouts(for: viewerPage)) { candidate in
                            layoutSwatchButton(candidate, currentPage: viewerPage)
                                .id(candidate.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, Self.layoutPickerVerticalPadding)
                }
                .frame(height: Self.layoutPickerHeight)
                // § "Nền khối bar sẫm hơn nền chính 1 chút, để các layout nổi phần viền trắng" —
                // a touch darker than the Page area's own `.systemGroupedBackground`, in both
                // light and dark mode, so each swatch's white border reads clearly against it
                // instead of blending in.
                .background(Color(.systemGroupedBackground).overlay(Color.black.opacity(0.06)))
                .onAppear {
                    scrollProxy.scrollTo(viewerPage.page.layoutId, anchor: .center)
                }
                .onChange(of: viewerPage.id) { _, _ in
                    // Switched to a different Page — snap to *that* Page's own current layout,
                    // no animation (it wasn't visible a moment ago anyway).
                    scrollProxy.scrollTo(viewerPage.page.layoutId, anchor: .center)
                }
                .onChange(of: viewerPage.page.layoutId) { _, newLayoutId in
                    // § "Layout được chọn sẽ căn giữa màn" — re-center on whichever layout just
                    // became selected for this same Page (a tap on a swatch elsewhere in the row).
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollProxy.scrollTo(newLayoutId, anchor: .center)
                    }
                }
            }
        }
    }

    private func candidateLayouts(for viewerPage: AlbumViewerPage) -> [AlbumPageLayout] {
        (try? layoutRepository.layouts(photoCount: viewerPage.page.assignments.count, format: viewerPage.page.format))?
            .sorted { $0.id < $1.id } ?? []
    }

    private func layoutSwatchButton(_ candidate: AlbumPageLayout, currentPage: AlbumViewerPage) -> some View {
        let isSelected = candidate.id == currentPage.page.layoutId
        return Button {
            apply(.changePageLayout(pageId: currentPage.page.id, layoutId: candidate.id), animated: true)
        } label: {
            AlbumPageRenderer(layout: candidate, assignments: Self.swatchAssignments(for: candidate), photoProvider: LayoutSwatchPhotoProvider())
                .frame(width: Self.layoutSwatchSize, height: Self.layoutSwatchSize)
                // § "Các layout không để border-radius" — square corners, no clipping/rounding.
                .clipShape(Rectangle())
                .overlay {
                    Rectangle()
                        .stroke(isSelected ? Color.accentColor : Color.white, lineWidth: isSelected ? 3 : 1.5)
                }
        }
        .buttonStyle(.plain)
    }

    /// One placeholder assignment per slot — never a real photo, just enough for
    /// `AlbumPageRenderer` to hand each slot to `LayoutSwatchPhotoProvider`, which colors it by
    /// the reference id's own stable hash. Keyed off `candidate.id`/`slot.id` (not a real photo
    /// id) so the same layout always swatches the same way.
    private static func swatchAssignments(for candidate: AlbumPageLayout) -> [AlbumPhotoAssignment] {
        candidate.slots.map { slot in
            AlbumPhotoAssignment(
                id: "swatch-\(candidate.id)-\(slot.id)", slotId: slot.id,
                photo: AlbumPhotoReference(id: "\(candidate.id)-\(slot.id)", source: .applePhotos, sourceIdentifier: "", originalFilename: nil),
                crop: .centered
            )
        }
    }

    private var editToolbar: some View {
        HStack(spacing: 0) {
            editToolbarButton("album.changeCover", systemImage: "photo") { changeCoverTarget = true }
            editToolbarButton("album.swapPhoto", systemImage: "arrow.left.arrow.right") {
                if let page = currentViewerPage { swapSourcePage = page }
            }
            .disabled(currentViewerPage == nil)
            editToolbarButton("album.removePhoto", systemImage: "minus.circle") {
                if let page = currentViewerPage { removePhotoTarget = page }
            }
            .disabled(currentViewerPage == nil)
            editToolbarButton("album.removeSpread", systemImage: "trash") {
                if let page = currentViewerPage { removeSpreadConfirmation = page }
            }
            .disabled(currentViewerPage == nil)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func editToolbarButton(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                Text(titleKey).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func beginEditing() {
        editingSession = AlbumEditingSession(draft: draft)
    }

    // This screen is only ever reached from `AlbumDetailView`, already in edit mode
    // (`startInEditMode: true`) — Save/Cancel both dismiss back to it rather than falling through
    // to this screen's own "view mode", which would otherwise leave the user stranded on the old
    // Page-by-page viewer instead of returning to the standard Album Detail screen.
    private func cancelEditing() {
        editingSession = nil
        dismiss()
    }

    private func saveEditing() async {
        guard let session = editingSession else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try AlbumDraftValidator.validate(session.workingDraft, repository: layoutRepository)
            var updated = session.workingDraft
            updated.updatedAt = Date()
            draft = updated
            editingSession = nil
            await onSave(updated)
            dismiss()
        } catch {
            editError = String(describing: error)
        }
    }

    /// `animated: true` (used only for `.changePageLayout` — § user request: "toạ độ frame layout
    /// cũ sẽ di chuyển đến toạ độ frame tương ứng của layout mới") wraps the actual state
    /// mutation in `withAnimation`, even though it lands asynchronously inside this `Task` — that
    /// still works, since `withAnimation` only cares that the state write itself happens
    /// synchronously *within* its trailing closure, not that the closure runs synchronously
    /// relative to the call site. Every other action stays unanimated (snap), matching how it's
    /// always behaved; `.swapPhotos` in particular already has its own dedicated ripple transition
    /// in `AlbumPageRenderer` that a blanket animation here would only fight with.
    private func apply(_ action: AlbumEditAction, animated: Bool = false) {
        guard let session = editingSession else { return }
        Task {
            do {
                let updated = try await actionApplier.apply(action, to: session.workingDraft)
                if animated {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        editingSession?.workingDraft = updated
                    }
                } else {
                    editingSession?.workingDraft = updated
                }
            } catch AlbumEditError.cannotRemoveLastPhotoOnPage {
                removePhotoBlockedAlert = true
            } catch {
                editError = String(describing: error)
            }
        }
    }

    private func removeSpread(containing page: AlbumViewerPage) {
        apply(.removeSpread(spreadId: page.spreadId))
    }
}
