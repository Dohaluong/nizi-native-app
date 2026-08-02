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

    @State private var cropTarget: AlbumPhotoCropTarget?
    @State private var textBlockEditTarget: AlbumTextBlockEditTarget?
    @State private var addPhotoTarget: AlbumViewerPage?
    @State private var addPhotoBlockedAlert = false
    @State private var removePageConfirmation: AlbumViewerPage?
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
        // § build note — this used to be one single `NavigationStack { ... } .onChange(...) ...`
        // expression; adding `.navigationDestination` pushed it over the type checker's "unable to
        // type-check in reasonable time" threshold. Splitting the `NavigationStack` itself out into
        // its own `some View` property gives the checker two smaller expressions to solve instead
        // of one large one — behaviorally identical, just faster to compile.
        navigationContent
            .onChange(of: activeDraft.spreads) { oldValue, _ in
                if let selectedItemId {
                    // § user report — "xoá trang xong ... chuyển đến trang cuối cùng" thay vì
                    // trang tiếp theo: `previousItems` (built from `oldValue`, the Spreads just
                    // before this change) is what lets `resolved(against:previousItems:)` land on
                    // whatever slid into the removed Page's old slot, instead of always falling
                    // back to the very last Page.
                    var draftBeforeChange = activeDraft
                    draftBeforeChange.spreads = oldValue
                    let previousItems = itemBuilder.makeItems(from: draftBeforeChange)
                    let resolved = AlbumViewerSelection(itemId: selectedItemId).resolved(against: items, previousItems: previousItems)
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
        .alert("album.edit.add_photo_blocked_title", isPresented: $addPhotoBlockedAlert) {
            Button("common.action.cancel", role: .cancel) {}
        } message: {
            Text("album.edit.add_photo_blocked_message")
        }
        .confirmationDialog(
            "album.edit.remove_page_title", isPresented: Binding(get: { removePageConfirmation != nil }, set: { if !$0 { removePageConfirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("album.removePage", role: .destructive) {
                if let page = removePageConfirmation { removeCurrentPage(page) }
                removePageConfirmation = nil
            }
            Button("common.action.cancel", role: .cancel) { removePageConfirmation = nil }
        } message: {
            // § user request — "Không xoá ảnh khỏi thiết bị, chỉ xoá khỏi album": this only ever
            // clears this one Page's own assignments in the Draft, never touches the Photos
            // Library asset itself.
            Text("album.photosRemainInLibrary")
        }
        .sheet(item: $addPhotoTarget) { targetPage in
            AlbumPhotoPickerSheet(draft: activeDraft, title: "album.addPhoto") { reference in
                apply(.addPhoto(pageId: targetPage.page.id, photo: reference))
                addPhotoTarget = nil
            }
        }
        .sheet(item: $textBlockEditTarget) { target in
            AlbumTextBlockEditSheet(
                target: target,
                onSave: { text, horizontalAlignment, verticalAlignment, fontFamily, fontSize, fontStyle, textColor in
                    if target.isCoverText {
                        apply(.updateCoverTextBlock(
                            textBlockId: target.textBlockId, text: text,
                            horizontalAlignment: horizontalAlignment, verticalAlignment: verticalAlignment,
                            fontFamily: fontFamily, fontSize: fontSize, fontStyle: fontStyle, textColor: textColor
                        ))
                    } else {
                        apply(.updateTextBlock(
                            pageId: target.pageId, textBlockId: target.textBlockId, text: text,
                            horizontalAlignment: horizontalAlignment, verticalAlignment: verticalAlignment,
                            fontFamily: fontFamily, fontSize: fontSize, fontStyle: fontStyle, textColor: textColor
                        ))
                    }
                    textBlockEditTarget = nil
                },
                onCancel: { textBlockEditTarget = nil }
            )
        }
    }

    private var navigationContent: some View {
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
            .background(AlbumEditorSurface.background)
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
            // § user report — was `.sheet(item:)`; a modal sheet's own interactive drag-to-dismiss
            // fought with panning the photo toward the bottom of the frame (a drag that couldn't
            // pan any further closed the whole screen instead of just stopping there). Pushed onto
            // this `NavigationStack` instead — a real screen, not a modal, so there's no competing
            // dismiss gesture at all. Must live *inside* the `NavigationStack` (unlike the `.sheet`s
            // on `body` itself, which don't care) — `.navigationDestination` only registers against
            // the enclosing stack's own push mechanism if it's actually part of that stack's content.
            .navigationDestination(item: $cropTarget) { target in
                cropDestination(target)
            }
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Items

    // § layout request — the page number now sits right below each Page's own content (as part
    // of the same `TabView` item, so it slides along with the Page it belongs to) instead of in a
    // persistent top header; the Cover has no page number, so it renders with nothing below it.
    //
    // § user request — "trang bìa sẽ có cấu trúc như trang ruột ... Có thể lấy layout id:
    // square.1.cover làm layout ban đầu": the Cover used to render via the now-deleted bespoke
    // `AlbumCoverView` (its own hardcoded gradient/shadow/title chrome, no crop, no per-block text
    // editing, and a corner radius that never matched the real layout's own — see `AlbumDetailView
    // .pagerContent`'s own doc comment). It's now just another `pageView` — the same
    // `AlbumPageRenderer` pipeline every content Page already goes through — fed a synthesized
    // `AlbumViewerPage` (`coverAsViewerPage`, via the shared `AlbumCoverPageBuilder`) instead of a
    // real one from `draft.spreads`, so corner radius, tap-to-crop, tap-to-change-photo, and
    // tap-to-edit-text all come for free, identical to a content Page. `AlbumDetailView`'s own
    // read-only hero now uses the same `AlbumCoverPageBuilder`/`AlbumPageCardView` pair for the
    // same reason; `AlbumCoverConfiguration` (unchanged) still feeds its `heroEyebrow`/
    // `overviewText`, which have nothing to do with the Cover's own on-screen rendering.
    @ViewBuilder
    private func itemView(_ item: AlbumViewerItem) -> some View {
        switch item {
        case .cover:
            pageView(coverAsViewerPage, showsPageIndicator: false)
        case let .page(viewerPage):
            pageView(viewerPage)
        }
    }

    /// Local aliases for `AlbumCoverPageBuilder`'s own constants — kept so every existing
    /// `Self.coverLayoutId`/`Self.coverPageId` comparison below reads the same as before.
    private static let coverLayoutId = AlbumCoverPageBuilder.layoutId
    private static let coverPageId = AlbumCoverPageBuilder.pageId

    /// § user request — "trang bìa sẽ có cấu trúc như trang ruột": shared with `AlbumDetailView`'s
    /// own read-only hero via `AlbumCoverPageBuilder`, so the synthesis logic (seeding title/
    /// subtitle/paragraph from the Album's own title/date/location, resolving `coverLayoutId`)
    /// never has to be duplicated between the two screens.
    private var coverAsViewerPage: AlbumViewerPage {
        AlbumCoverPageBuilder.makeViewerPage(from: activeDraft, layoutRepository: layoutRepository)
    }

    /// Broken out from `body`'s `.navigationDestination` closure — inlined there, the whole
    /// `body` expression became too large for the type checker to resolve in reasonable time.
    private func cropDestination(_ target: AlbumPhotoCropTarget) -> some View {
        AlbumPhotoCropSheet(
            assignment: target.assignment, frameAspectRatio: target.frameAspectRatio, draft: activeDraft,
            onSave: { crop in
                if target.isCoverPhoto {
                    apply(.updateCoverPhotoCrop(crop: crop))
                } else {
                    apply(.updatePhotoCrop(assignmentId: target.assignment.id, crop: crop))
                }
                cropTarget = nil
            },
            onCancel: { cropTarget = nil },
            // § user request — "trang bìa ... crop ảnh tương tự như trang khác": the cover always
            // needs exactly one photo, so there's no "remove" action for it at all (see
            // `AlbumPhotoCropSheet.onRemove`'s own doc comment).
            onRemove: target.isCoverPhoto ? nil : {
                apply(.removePhoto(pageId: target.pageId, slotId: target.assignment.slotId))
                cropTarget = nil
            },
            onChangePhoto: { photo in
                if target.isCoverPhoto {
                    apply(.changeCover(photo: photo))
                } else {
                    apply(.assignPhoto(assignmentId: target.assignment.id, photo: photo))
                }
                cropTarget = nil
            }
        )
    }

    /// `showsPageIndicator: false` for the Cover (§ layout request, unchanged) — everything else
    /// is identical for the Cover and a content Page; the only branching left is *which*
    /// `AlbumEditAction` a crop/text-edit dispatches to, decided by `isCoverPage` below and
    /// threaded through via `AlbumPhotoCropTarget.isCoverPhoto`/`AlbumTextBlockEditTarget.
    /// isCoverText` (see `cropDestination` and the `textBlockEditTarget` sheet in `body`).
    private func pageView(_ viewerPage: AlbumViewerPage, showsPageIndicator: Bool = true) -> some View {
        let isCoverPage = viewerPage.page.id == Self.coverPageId
        return VStack(spacing: 6) {
            AlbumPageCardView(
                viewerPage: viewerPage, layoutRepository: layoutRepository,
                // § user request — drag-to-swap only while actively editing; outside edit mode
                // `apply(_:)` would silently no-op anyway (no `editingSession`), which would
                // leave the ripple's "new photo" reveal showing the same old photo underneath.
                // The Cover has only ever one photo (its single slot), so there's never a second
                // assignment on the same "Page" to swap with.
                onSwapPhotos: (isEditing && !isCoverPage)
                    ? { from, to in apply(.swapPhotos(firstAssignmentId: from.id, secondAssignmentId: to.id)) }
                    : nil,
                onCropPhoto: isEditing
                    ? { assignment, aspectRatio in
                        cropTarget = AlbumPhotoCropTarget(
                            assignment: assignment, frameAspectRatio: aspectRatio, pageId: viewerPage.page.id,
                            isCoverPhoto: isCoverPage
                        )
                    }
                    : nil,
                onDragActiveChanged: { isPhotoDragActive = $0 },
                onTapTextBlock: isEditing
                    ? { effective, kind in
                        textBlockEditTarget = AlbumTextBlockEditTarget(
                            pageId: viewerPage.page.id, textBlockId: effective.textBlockId, currentText: effective.text,
                            currentHorizontalAlignment: effective.horizontalAlignment, currentVerticalAlignment: effective.verticalAlignment,
                            currentFontFamily: effective.fontFamily, currentFontSize: effective.fontSize, currentFontStyle: effective.fontStyle,
                            currentTextColor: effective.textColor, currentKind: kind, isCoverText: isCoverPage
                        )
                    }
                    : nil,
                onTapBlankPage: isEditing ? { beginAddPhoto(to: viewerPage) } : nil
            )
            if showsPageIndicator {
                Text(localizedString("album.viewer.page_indicator", defaultValue: "Page \(viewerPage.pageNumber) / \(viewerPage.totalPageCount)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        // Must be a genuine descendant of this Page's own `TabView` item (see
        // `AlbumPagingLockView`'s own doc comment) so walking `superview` from it resolves to
        // *this* Page's own `UIPageViewController`-backed `UIScrollView`, not some unrelated one.
        .background(AlbumPagingLockView(isLocked: isPhotoDragActive))
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7)
    }

    // MARK: - Edit mode

    /// Only ever a real Page from `draft.spreads` — deliberately `nil` while the Cover is showing.
    /// The layout picker needs the Cover included too, so it has its own separate resolution
    /// (`layoutPickerViewerPage`) rather than widening this one.
    private var currentViewerPage: AlbumViewerPage? {
        guard case let .page(page) = items.first(where: { $0.id == selectedItemId }) else { return nil }
        return page
    }

    /// § user request — "square.1.cover là layout mặc định cho ảnh bìa, sau này có thể thay layout
    /// khác": unlike `currentViewerPage`, this *does* resolve to `coverAsViewerPage` while the
    /// Cover is showing, so `layoutPickerHeader` below can offer the same swatch row for it.
    private var layoutPickerViewerPage: AlbumViewerPage? {
        // `AlbumViewerItem.cover`'s own `id` is the literal `"cover"` string — same sentinel
        // `Self.coverPageId` already uses, so this is just comparing against that directly.
        selectedItemId == Self.coverPageId ? coverAsViewerPage : currentViewerPage
    }

    /// § layout request — replaces the old "Change Layout" sheet with an always-visible picker at
    /// the top of the screen: one horizontal row (free to run wider than the screen — pan to see
    /// the rest) of every layout that matches the *current* Page's own photo count (never a
    /// mismatched count — same filter `AlbumLayoutPickerSheet` used to apply), re-filtering
    /// automatically as `layoutPickerViewerPage` changes while swiping between Pages. Tapping a
    /// swatch applies it immediately, no confirmation step, and re-centers the row on it. § user
    /// request — "square.1.cover là layout mặc định cho ảnh bìa, sau này có thể thay layout khác":
    /// now also shown for the Cover (`layoutSwatchButton` branches which `AlbumEditAction` a tap
    /// dispatches to).
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
        if let viewerPage = layoutPickerViewerPage {
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
                .background(AlbumEditorSurface.layoutPickerBackground)
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
            if currentPage.page.id == Self.coverPageId {
                apply(.changeCoverLayout(layoutId: candidate.id), animated: true)
            } else {
                apply(.changePageLayout(pageId: currentPage.page.id, layoutId: candidate.id), animated: true)
            }
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
    /// `AlbumPageRenderer` to hand each slot to `LayoutSwatchPhotoProvider`, which renders it as a
    /// blue gradient placeholder. Keyed off `candidate.id`/`slot.id` (not a real photo id) so the
    /// same layout always swatches the same way.
    private static func swatchAssignments(for candidate: AlbumPageLayout) -> [AlbumPhotoAssignment] {
        candidate.slots.map { slot in
            AlbumPhotoAssignment(
                id: "swatch-\(candidate.id)-\(slot.id)", slotId: slot.id,
                photo: AlbumPhotoReference(id: "\(candidate.id)-\(slot.id)", source: .applePhotos, sourceIdentifier: "", originalFilename: nil),
                crop: .centered
            )
        }
    }

    // MARK: - Bottom toolbar (Add Photo / Delete Page)

    /// § user request — "1 nút thêm ảnh bên dưới cùng, ở chính giữa, dạng icon không có chữ" +
    /// "1 nút xoá trang": a single centered Add-Photo button (the primary action here), plus a
    /// Delete-Page button pinned to the trailing edge — both icon-only, both Page-only (disabled
    /// while the Cover is showing, same as every other `currentViewerPage`-gated action).
    private var editToolbar: some View {
        ZStack {
            addPhotoButton
            HStack {
                Spacer()
                deletePageButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var addPhotoButton: some View {
        Button {
            if let page = currentViewerPage { beginAddPhoto(to: page) }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 32))
        }
        .disabled(currentViewerPage == nil)
        .accessibilityLabel(Text("album.addPhoto"))
    }

    private var deletePageButton: some View {
        Button(role: .destructive) {
            if let page = currentViewerPage { removePageConfirmation = page }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 20))
        }
        .disabled(currentViewerPage == nil)
        .accessibilityLabel(Text("album.removePage"))
    }

    /// Shared by the centered "+" toolbar button and tapping a blank Page's own placeholder card
    /// directly (`AlbumPageCardView.onTapBlankPage`) — both just want "open the picker for this
    /// Page," gated the same way.
    private func beginAddPhoto(to viewerPage: AlbumViewerPage) {
        if canAddPhoto(to: viewerPage) {
            addPhotoTarget = viewerPage
        } else {
            addPhotoBlockedAlert = true
        }
    }

    /// § user request — "Không cho thêm nếu quá giới hạn frame ảnh": true only if some layout in
    /// this Page's format supports one more slot than it currently has (§ layouts top out at
    /// `photoCount` 4 today, so a 4-photo Page always reports `false` here).
    private func canAddPhoto(to viewerPage: AlbumViewerPage) -> Bool {
        let nextCount = viewerPage.page.assignments.count + 1
        return !((try? layoutRepository.layouts(photoCount: nextCount, format: viewerPage.page.format)) ?? []).isEmpty
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
            } catch {
                editError = String(describing: error)
            }
        }
    }

    /// § user report — "dù đã xoá spread nhưng ra ngoài album vẫn thấy đủ chưa xoá và vẫn vào lại
    /// được": every other edit action only ever touches `editingSession.workingDraft`, discarded
    /// whole by `cancelEditing()` unless the user separately taps "Save" — for most edits that's
    /// fine (Cancel is supposed to discard them), but a destructive action the user already
    /// confirmed through its own "are you sure?" dialog reads as final the moment they tap it, not
    /// contingent on a second, unrelated Save tap. So this persists immediately (`draft`/`onSave`,
    /// the same two writes `saveEditing()` itself does, minus validation/dismiss) — same posture
    /// `AlbumDetailView`'s own direct-commit actions (`hidePhoto`, photo replace) already take.
    private func removeCurrentPage(_ page: AlbumViewerPage) {
        guard let session = editingSession else { return }
        Task {
            do {
                let updated = try await actionApplier.apply(.removePage(pageId: page.page.id), to: session.workingDraft)
                editingSession?.workingDraft = updated
                draft = updated
                await onSave(updated)
            } catch {
                editError = String(describing: error)
            }
        }
    }
}

private enum AlbumEditorSurface {
    static let background = Color(red: 246 / 255, green: 244 / 255, blue: 239 / 255)
    // A slightly deeper neutral behind the white layout swatches makes their silhouette clear
    // while staying within the light Photobook surface.
    static let layoutPickerBackground = Color(red: 225 / 255, green: 222 / 255, blue: 215 / 255)
}
