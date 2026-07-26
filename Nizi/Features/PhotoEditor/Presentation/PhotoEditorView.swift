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
/// Sprint 2–6 (Editor + Rendering foundation + Preset + Adjust + Auto Enhance) scope: load a real
/// Core-Image-rendered preview, Cancel/Save, press-and-hold to view the original, unsaved-change
/// detection, a Preset strip, the six Adjust sliders, and on-device Auto Enhance. No Album/Event
/// integration or collection style yet (Bước 8–9).
struct PhotoEditorView: View {
    /// Which tool tray is currently showing below the image (§ 6.4: Preset is always the default
    /// tab on open). Not part of `PhotoEditorViewModel` — which tab is selected is pure View state
    /// with no bearing on the edit itself, unlike everything the view model owns.
    private enum EditorTool: String, CaseIterable, Identifiable {
        case preset
        case adjust
        case auto
        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .preset: "photoEditor.tool.preset"
            case .adjust: "photoEditor.tool.adjust"
            case .auto: "photoEditor.tool.auto"
            }
        }
    }

    let onClose: (PhotoEditorResult) -> Void

    @State private var viewModel: PhotoEditorViewModel
    @State private var showDiscardConfirmation = false
    @State private var selectedTool: EditorTool = .preset

    init(
        context: EditorContext,
        renderEngine: PhotoRendering? = nil,
        repository: PhotoEditRepository = InMemoryPhotoEditRepository(),
        presetRepository: PresetRepository = BundlePresetRepository(),
        autoEnhanceService: AutoEnhancing = AutoEnhanceService(),
        onClose: @escaping (PhotoEditorResult) -> Void
    ) {
        self.onClose = onClose
        // `renderEngine` defaults through `presetRepository` (not its own separate default) so a
        // caller overriding `presetRepository` — e.g. a future test double — doesn't end up with
        // the render engine and the view model resolving presets from two different catalogs.
        let resolvedRenderEngine = renderEngine ?? PhotoRenderEngine(presetRepository: presetRepository)
        _viewModel = State(initialValue: PhotoEditorViewModel(
            context: context, renderEngine: resolvedRenderEngine, repository: repository,
            presetRepository: presetRepository, autoEnhanceService: autoEnhanceService
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

    private var toolTray: some View {
        VStack(spacing: 0) {
            toolPicker
            switch selectedTool {
            case .preset:
                PresetStripView(viewModel: viewModel)
            case .adjust:
                AdjustPanelView(viewModel: viewModel)
            case .auto:
                AutoEnhancePanelView(viewModel: viewModel)
            }
        }
    }

    private var toolPicker: some View {
        HStack(spacing: 0) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Text(localizedString(dynamicKey: tool.titleKey))
                        .font(.subheadline.weight(selectedTool == tool ? .semibold : .regular))
                        .foregroundStyle(selectedTool == tool ? Color.primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
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
