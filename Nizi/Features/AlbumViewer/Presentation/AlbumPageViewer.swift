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
    @State private var changeLayoutTarget: AlbumViewerPage?
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
            .safeAreaInset(edge: .top) { header }
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
        .sheet(item: $changeLayoutTarget) { page in
            AlbumLayoutPickerSheet(page: page.page, layoutRepository: layoutRepository) { layoutId in
                apply(.changePageLayout(pageId: page.page.id, layoutId: layoutId))
                changeLayoutTarget = nil
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 2) {
            Text(activeDraft.title)
                .font(.subheadline.bold())
            Text(pageIndicatorText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var pageIndicatorText: String {
        guard let currentItem = items.first(where: { $0.id == selectedItemId }) else { return "" }
        switch currentItem {
        case .cover:
            return String(localized: "album.viewer.cover_indicator")
        case let .page(page):
            return localizedString("album.viewer.page_indicator", defaultValue: "Page \(page.pageNumber) / \(page.totalPageCount)")
        }
    }

    // MARK: - Items

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
        AlbumPageCardView(viewerPage: viewerPage, layoutRepository: layoutRepository)
    }

    // MARK: - Edit mode

    private var currentViewerPage: AlbumViewerPage? {
        guard case let .page(page) = items.first(where: { $0.id == selectedItemId }) else { return nil }
        return page
    }

    private var editToolbar: some View {
        HStack(spacing: 0) {
            editToolbarButton("album.changeCover", systemImage: "photo") { changeCoverTarget = true }
            editToolbarButton("album.changeLayout", systemImage: "square.grid.2x2") {
                if let page = currentViewerPage { changeLayoutTarget = page }
            }
            .disabled(currentViewerPage == nil)
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
