//
//  PhotoEditorView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// Photo Editor's entry point — openable from Album, Event, or standalone via `EditorContext`
/// alone (PHOTO-EDITOR.md § 4). Callers present this with `.fullScreenCover(item:)`/
/// `.fullScreenCover(isPresented:)`, the same idiom `AlbumPhotoPreviewView` and
/// `CurationPreviewView` already use for their own full-screen presentation, and read the result
/// back through `onClose`.
///
/// Sprint 2–8 scope: load a real Core-Image-rendered preview, Cancel/Save, press-and-hold to view
/// the original, unsaved-change detection, a Preset strip, the six Adjust sliders, on-device Auto
/// Enhance, and — when opened from an Album or Event — the save-scope choice (§ 11) between just
/// this photo and applying the chosen style to the whole collection. No collection-style
/// inheritance/override resolution for *displaying* already-styled photos outside the editor yet
/// (Bước 9) — this sprint only covers the editor's own save flow and persistence.
struct PhotoEditorView: View {
    /// Which tool tray is currently showing below the image (§ 6.4: Preset is always the default
    /// tab on open). Not part of `PhotoEditorViewModel` — which tab is selected is pure View state
    /// with no bearing on the edit itself, unlike everything the view model owns.
    private enum EditorTool: String, CaseIterable, Identifiable {
        case preset
        case adjust
        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .preset: "photoEditor.tool.preset"
            case .adjust: "photoEditor.tool.adjust"
            }
        }
    }

    let onClose: (PhotoEditorResult) -> Void

    @State private var viewModel: PhotoEditorViewModel
    @State private var showDiscardConfirmation = false
    @State private var showSaveScopeSheet = false
    @State private var selectedTool: EditorTool = .preset

    /// Pinch-to-zoom state for `imageArea` — `committedZoom`/`committedPanOffset` are what's left
    /// in effect between gestures; `pinchMagnification`/`panTranslation` are the in-flight delta of
    /// whatever gesture is currently active, summed on top via `currentZoom`/`currentPanOffset`.
    /// Deliberately not reset on every re-render (preset switch, slider drag) — staying zoomed in
    /// on, say, a face while tweaking Adjust sliders is the whole point.
    @State private var committedZoom: CGFloat = 1
    @GestureState private var pinchMagnification: CGFloat = 1
    @State private var committedPanOffset: CGSize = .zero
    @GestureState private var panTranslation: CGSize = .zero

    private static let minZoom: CGFloat = 1
    private static let maxZoom: CGFloat = 5

    private var currentZoom: CGFloat { committedZoom * pinchMagnification }
    private var currentPanOffset: CGSize {
        CGSize(
            width: committedPanOffset.width + panTranslation.width,
            height: committedPanOffset.height + panTranslation.height
        )
    }

    init(
        context: EditorContext,
        renderEngine: PhotoRendering? = nil,
        repository: PhotoEditRepository = InMemoryPhotoEditRepository(),
        presetRepository: PresetRepository = BundlePresetRepository(),
        autoEnhanceService: AutoEnhancing = AutoEnhanceService(),
        collectionStyleRepository: CollectionStyleRepository = InMemoryCollectionStyleRepository(),
        onClose: @escaping (PhotoEditorResult) -> Void
    ) {
        self.onClose = onClose
        // `renderEngine` defaults through `presetRepository` (not its own separate default) so a
        // caller overriding `presetRepository` — e.g. a future test double — doesn't end up with
        // the render engine and the view model resolving presets from two different catalogs.
        let resolvedRenderEngine = renderEngine ?? PhotoRenderEngine(presetRepository: presetRepository)
        _viewModel = State(initialValue: PhotoEditorViewModel(
            context: context, renderEngine: resolvedRenderEngine, repository: repository,
            presetRepository: presetRepository, autoEnhanceService: autoEnhanceService,
            collectionStyleRepository: collectionStyleRepository
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                imageArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                toolTray
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar { toolbarContent }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle(Text("photoEditor.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await viewModel.loadPreview() }
        .confirmationDialog(
            "photoEditor.discardChanges.title",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("photoEditor.discardChanges.keepEditing", role: .cancel) {}
            Button("photoEditor.discardChanges.discard", role: .destructive) {
                onClose(viewModel.discardChanges())
            }
        }
        .overlay {
            if showSaveScopeSheet {
                saveScopeOverlay
            }
        }
        .animation(.easeOut(duration: 0.2), value: showSaveScopeSheet)
    }

    /// § 11.2/11.4's save-scope choice, as a small modal card centered on screen — not a bottom
    /// sheet. `SaveScopeSheet` only ever contains a handful of buttons/a picker, so a half-screen
    /// `.presentationDetents([.medium])` sheet left most of its own sheet empty; a card sized to
    /// its own content and dimmed-background-dismissible reads as the deliberate, small choice it
    /// actually is.
    private var saveScopeOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showSaveScopeSheet = false }

            SaveScopeSheet(
                sourceType: viewModel.context.sourceType,
                presetName: selectedPresetDisplayName,
                presetIntensityPercent: Int(viewModel.presetIntensityPercent.rounded()),
                onSaveThisPhotoOnly: { overwrite in
                    showSaveScopeSheet = false
                    Task { await finishSave { await viewModel.saveAsNewAsset(overwrite: overwrite) } }
                },
                onCancel: { showSaveScopeSheet = false }
            )
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("common.action.cancel") { handleCancelTapped() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("album.save") { handleSaveTapped() }
                .disabled(!viewModel.hasUnsavedChanges || viewModel.isSaving)
        }
    }

    private func handleCancelTapped() {
        if viewModel.hasUnsavedChanges {
            showDiscardConfirmation = true
        } else {
            onClose(viewModel.discardChanges())
        }
    }

    /// § 4.3 — the save-scope choice only exists when this editor was opened from an Album or
    /// Event; a standalone edit saves immediately, exactly like Sprint 2's original single-photo
    /// Save behavior.
    private func handleSaveTapped() {
        switch viewModel.context.sourceType {
        case .standalone:
            Task { await finishSave(using: viewModel.saveThisPhotoOnly) }
        case .album, .event:
            showSaveScopeSheet = true
        }
    }

    private func finishSave(using saveAction: () async -> PhotoEditorResult) async {
        let result = await saveAction()
        if result.didSave {
            onClose(result)
        }
    }

    private var selectedPresetDisplayName: String {
        guard let preset = viewModel.presets.first(where: { $0.id == viewModel.selectedPresetId }) else {
            return viewModel.selectedPresetId
        }
        return localizedString(dynamicKey: preset.nameKey, defaultValue: preset.name)
    }

    private var toolTray: some View {
        VStack(spacing: 0) {
            toolPicker
            // Height is applied exactly once, here, never inside `PresetStripView`/
            // `AdjustPanelView` themselves — that's what makes switching tabs change only the
            // content, never the surrounding height.
            Group {
                switch selectedTool {
                case .preset:
                    PresetStripView(viewModel: viewModel)
                case .adjust:
                    AdjustPanelView(viewModel: viewModel)
                }
            }
            .frame(height: PhotoEditorToolTrayMetrics.contentHeight)
        }
        // One background for the tab picker and the content together — no separate light bar
        // sitting on top of the dark tray, no seam between the two.
        .background(PhotoEditorToolTrayMetrics.background)
    }

    private var toolPicker: some View {
        HStack(spacing: 0) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Text(localizedString(dynamicKey: tool.titleKey))
                        .font(.subheadline.weight(selectedTool == tool ? .semibold : .regular))
                        .foregroundStyle(selectedTool == tool ? Color.white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView()
                .tint(.white)
        case .failed:
            failedView
        case let .loaded(cgImage):
            GeometryReader { proxy in
                // `Image(decorative:scale:orientation:)`, not `Image(uiImage:)` — the render
                // engine already hands back a `CGImage`, so wrapping it in a `UIImage` first would
                // be exactly the unnecessary `CIImage`/`UIImage`-adjacent conversion § 18.3 asks
                // to avoid. Orientation is always `.up`: `PhotoRenderEngine` normalizes rotation
                // into the pixels themselves before this ever reaches the View.
                Image(decorative: cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(currentZoom)
                    .offset(currentPanOffset)
                    .clipped()
            }
            .overlay(alignment: .bottom) { originalBadge }
            // Press-and-hold, matching § 6.3's "chạm giữ để xem ảnh gốc / nhả tay quay lại":
            // `minimumDuration: 0` makes this fire on touch-down rather than after a real
            // long-press, since the requirement is immediate press feedback, not a held-for-
            // N-seconds gesture.
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
            } onPressingChanged: { isPressing in
                viewModel.setShowingOriginal(isPressing)
            }
            // Two-finger pinch-to-zoom + pan, layered on with `.simultaneousGesture` (not
            // `.gesture`) so it never steals the press-and-hold recognizer above — both need to
            // fire off the same touches (e.g. pinch-zooming and then holding to compare).
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(panGesture)
        }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchMagnification) { value, state, _ in state = value }
            .onEnded { value in
                committedZoom = min(max(committedZoom * value, Self.minZoom), Self.maxZoom)
                if committedZoom <= Self.minZoom {
                    withAnimation(.spring(duration: 0.25)) { committedPanOffset = .zero }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($panTranslation) { value, state, _ in
                guard committedZoom > Self.minZoom else { return }
                state = value.translation
            }
            .onEnded { value in
                guard committedZoom > Self.minZoom else { return }
                committedPanOffset.width += value.translation.width
                committedPanOffset.height += value.translation.height
            }
    }

    @ViewBuilder
    private var originalBadge: some View {
        if viewModel.isShowingOriginal {
            Text("photoEditor.original.badge")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 16)
        }
    }

    private var failedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
            Text("photoEditor.loadFailed")
                .font(.subheadline)
            Button("common.action.retry") { Task { await viewModel.loadPreview() } }
        }
        .foregroundStyle(.white)
    }
}
