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
/// Sprint 2–4 (Editor + Rendering foundation + Preset) scope: load a real Core-Image-rendered
/// preview, Cancel/Save, press-and-hold to view the original, unsaved-change detection, and a
/// Preset strip (< 10 presets, 0–100% intensity, thumbnails rendered from this photo). No
/// Adjust/Auto tools yet (Bước 5–6) — the tool tray below the image is Preset-only for now,
/// rather than a multi-tab picker with two tabs showing nothing.
struct PhotoEditorView: View {
    let onClose: (PhotoEditorResult) -> Void

    @State private var viewModel: PhotoEditorViewModel
    @State private var showDiscardConfirmation = false

    init(
        context: EditorContext,
        renderEngine: PhotoRendering? = nil,
        repository: PhotoEditRepository = InMemoryPhotoEditRepository(),
        presetRepository: PresetRepository = BundlePresetRepository(),
        onClose: @escaping (PhotoEditorResult) -> Void
    ) {
        self.onClose = onClose
        // `renderEngine` defaults through `presetRepository` (not its own separate default) so a
        // caller overriding `presetRepository` — e.g. a future test double — doesn't end up with
        // the render engine and the view model resolving presets from two different catalogs.
        let resolvedRenderEngine = renderEngine ?? PhotoRenderEngine(presetRepository: presetRepository)
        _viewModel = State(initialValue: PhotoEditorViewModel(
            context: context, renderEngine: resolvedRenderEngine, repository: repository, presetRepository: presetRepository
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                imageArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PresetStripView(viewModel: viewModel)
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("common.action.cancel") { handleCancelTapped() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("album.save") { Task { await handleSaveTapped() } }
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

    private func handleSaveTapped() async {
        let result = await viewModel.save()
        if result.didSave {
            onClose(result)
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
