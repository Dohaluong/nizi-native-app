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
                    : nil
            )
            Text(localizedString("album.viewer.page_indicator", defaultValue: "Page \(viewerPage.pageNumber) / \(viewerPage.totalPageCount)"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Edit mode

    private var currentViewerPage: AlbumViewerPage? {
        guard case let .page(page) = items.first(where: { $0.id == selectedItemId }) else { return nil }
        return page
    }

    /// § layout request — replaces the old "Change Layout" sheet with an always-visible picker at
    /// the top of the screen: 2 rows of every layout that matches the *current* Page's own photo
    /// count (never a mismatched count — same filter `AlbumLayoutPickerSheet` used to apply),
    /// re-filtering automatically as `currentViewerPage` changes while swiping between Pages.
    /// Tapping a swatch applies it immediately, no confirmation step. Empty (no picker at all)
    /// while the Cover is showing, since a Cover has no interchangeable Page layout.
    private static let layoutSwatchSize: CGFloat = 56
    private static let layoutSwatchRowSpacing: CGFloat = 8
    private static let layoutPickerVerticalPadding: CGFloat = 10
    /// Explicit, computed height — `LazyHGrid` inside a `ScrollView` with no bounded height left
    /// `.safeAreaInset` to size this however it liked (observed: it claimed nearly the whole
    /// screen, pushing the actual Page content out and leaving the 2 short rows of swatches
    /// vertically centered in all that extra space instead of forming a compact bar). A `LazyHGrid`
    /// needs a definite cross-axis size from its container to lay out predictably; this supplies
    /// exactly the 2 rows' own height (+ the padding below) instead of leaving it ambiguous.
    private static var layoutPickerHeight: CGFloat {
        layoutSwatchSize * 2 + layoutSwatchRowSpacing + layoutPickerVerticalPadding * 2
    }

    @ViewBuilder
    private var layoutPickerHeader: some View {
        if let viewerPage = currentViewerPage {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [GridItem(.fixed(Self.layoutSwatchSize), spacing: Self.layoutSwatchRowSpacing), GridItem(.fixed(Self.layoutSwatchSize), spacing: Self.layoutSwatchRowSpacing)],
                    spacing: 10
                ) {
                    ForEach(candidateLayouts(for: viewerPage)) { candidate in
                        layoutSwatchButton(candidate, currentPage: viewerPage)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, Self.layoutPickerVerticalPadding)
            }
            .frame(height: Self.layoutPickerHeight)
            .background(.bar)
        }
    }

    private func candidateLayouts(for viewerPage: AlbumViewerPage) -> [AlbumPageLayout] {
        (try? layoutRepository.layouts(photoCount: viewerPage.page.assignments.count, format: viewerPage.page.format))?
            .sorted { $0.id < $1.id } ?? []
    }

    private func layoutSwatchButton(_ candidate: AlbumPageLayout, currentPage: AlbumViewerPage) -> some View {
        Button {
            apply(.changePageLayout(pageId: currentPage.page.id, layoutId: candidate.id))
        } label: {
            AlbumPageRenderer(layout: candidate, assignments: Self.swatchAssignments(for: candidate), photoProvider: LayoutSwatchPhotoProvider())
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(candidate.id == currentPage.page.layoutId ? Color.accentColor : .clear, lineWidth: 3)
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
            editToolbarButton("album.removePhoto", systemImage: "photo.badge.minus") {
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

    private func apply(_ action: AlbumEditAction) {
        guard let session = editingSession else { return }
        Task {
            do {
                let updated = try await actionApplier.apply(action, to: session.workingDraft)
                editingSession?.workingDraft = updated
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
