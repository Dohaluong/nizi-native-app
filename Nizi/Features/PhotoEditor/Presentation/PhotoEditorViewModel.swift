//
//  PhotoEditorViewModel.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import Foundation
import Observation

/// What's currently on screen for the photo being edited. Not `Equatable` on the image itself
/// beyond reference identity — two `.loaded` states are only ever compared to detect "has the
/// underlying `CGImage` instance changed," never for value equality of pixels.
enum PhotoEditorLoadState: Equatable {
    case loading
    case loaded(CGImage)
    case failed

    static func == (lhs: PhotoEditorLoadState, rhs: PhotoEditorLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.failed, .failed):
            return true
        case let (.loaded(left), .loaded(right)):
            return left === right
        default:
            return false
        }
    }
}

/// Owns one editing session's state — the first `@Observable` view model in this codebase (every
/// other feature keeps state directly in a View's own `@State`). Introduced here specifically
/// because PHOTO-EDITOR.md § 14.1 calls out `PhotoEditorViewModel` as its own component distinct
/// from the View, and because it needs a place to own long-lived render `Task`s that must outlive
/// any single SwiftUI page being recycled — the same lesson `CurationPreviewView` already learned
/// the hard way for its own image-loading tasks (see docs/modules/PHOTO-EDITOR-IMPLEMENTATION-
/// PLAN.md § 1.5, § 7).
///
/// `@MainActor` since every property here drives UI directly; `renderEngine`/`repository`/
/// `presetRepository` are `Sendable` and do their own actor-hopping internally.
@MainActor
@Observable
final class PhotoEditorViewModel {
    let context: EditorContext

    private(set) var session: PhotoEditSession
    private(set) var loadState: PhotoEditorLoadState = .loading
    private(set) var isSaving = false
    /// Toggled by the press-and-hold gesture in `PhotoEditorView`; set through
    /// `setShowingOriginal(_:)`, never assigned directly, so every change reliably triggers a
    /// preview refresh.
    private(set) var isShowingOriginal = false

    private(set) var presets: [PresetDefinition] = []
    /// Rendered from *this* photo, not a fixed asset (ADDEDUM.md § 11) — keyed by preset id,
    /// session-lifetime only, never persisted to disk.
    private(set) var presetThumbnails: [String: CGImage] = [:]

    private let renderEngine: PhotoRendering
    private let repository: PhotoEditRepository
    private let presetRepository: PresetRepository

    /// Cancels/supersedes any preview render still in flight when a newer one is requested — see
    /// `refreshPreview()`. A monotonic counter rather than relying solely on `Task` cancellation
    /// propagating through `PhotoRenderEngine`'s own PHImageManager cancellation: it's simpler to
    /// reason about and race-free even if the underlying cancellation is slow or best-effort.
    private var renderGeneration = 0
    /// Same idea, scoped to the preset-thumbnail batch — bumped whenever thumbnails need
    /// regenerating from scratch (never expected to happen twice per session in V1, but keeps the
    /// same discard-stale-results guarantee `refreshPreview` has).
    private var thumbnailGeneration = 0

    /// Matches the existing viewers' `displayPreview` ceiling (`EventDetailView.ImageSizing`) —
    /// deliberately capped well below full device resolution; requesting at full screen
    /// resolution was the documented cause of slow/failed iCloud-backed loads elsewhere in this
    /// app, and there is no reason Photo Editor's own preview would be exempt from that.
    static let previewTargetSize = CGSize(width: 1000, height: 1000)
    /// ADDEDUM § 11 — "khoảng 100–160 px tùy màn hình."
    static let presetThumbnailSize = CGSize(width: 160, height: 160)

    init(
        context: EditorContext,
        renderEngine: PhotoRendering,
        repository: PhotoEditRepository,
        presetRepository: PresetRepository
    ) {
        self.context = context
        self.renderEngine = renderEngine
        self.repository = repository
        self.presetRepository = presetRepository
        session = PhotoEditSession(photoId: context.photoId, existingRecipe: nil)
    }

    var hasUnsavedChanges: Bool { session.hasUnsavedChanges }

    /// `nil` `presetId` displays as Original — never a separate "no selection" state (spec § 7.4:
    /// Original is always a real, selectable entry, not the absence of one).
    var selectedPresetId: String { session.workingRecipe.presetId ?? PresetDefinition.originalId }

    /// UI-facing `0...100` — the engine's own `presetIntensity` stays `0...1` (§ 10). Setting this
    /// triggers a debounced re-render; reading it never does.
    var presetIntensityPercent: Double {
        get { Double(session.workingRecipe.presetIntensity) * 100 }
        set {
            let clamped = min(max(newValue, 0), 100)
            session.workingRecipe.presetIntensity = Float(clamped / 100)
            Task { await refreshPreview(debounced: true) }
        }
    }

    /// Loads any previously saved recipe for this photo (so reopening the editor on an
    /// already-edited photo picks up where it left off, § 6.4's "phục hồi trạng thái đã lưu"),
    /// then renders the first preview and the preset thumbnail strip.
    func loadPreview() async {
        loadState = .loading
        presets = (try? presetRepository.loadPresets()) ?? []

        do {
            let existingRecipe = try await repository.getRecipe(photoId: context.photoId)
            session = PhotoEditSession(photoId: context.photoId, existingRecipe: existingRecipe)
        } catch {
            NiziLogger.photoEditor.error("photo_editor_recipe_load_failed photoId=\(self.context.photoId, privacy: .private) error=\(String(describing: error), privacy: .public)")
            loadState = .failed
            return
        }

        await refreshPreview()
        await loadPresetThumbnails()
    }

    /// The press-and-hold entry point — never mutate `isShowingOriginal` directly, since the
    /// point of holding is that it must actually re-render.
    func setShowingOriginal(_ showingOriginal: Bool) {
        guard isShowingOriginal != showingOriginal else { return }
        isShowingOriginal = showingOriginal
        Task { await refreshPreview() }
    }

    /// Selecting a preset never touches `adjustments` (§ 7.5: "Đổi preset không xóa Adjust").
    /// Re-tapping the already-selected preset lands on the same default-intensity state as a fresh
    /// select would, which doubles as § 7.5's optional "double tap để đưa intensity về giá trị mặc
    /// định" — offered as a plain re-tap instead of a separate double-tap gesture recognizer.
    func selectPreset(_ preset: PresetDefinition) {
        session.workingRecipe.presetId = preset.isOriginal ? nil : preset.id
        session.workingRecipe.presetIntensity = preset.isOriginal ? 0 : preset.defaultIntensity
        Task { await refreshPreview() }
    }

    /// Re-renders the preview for whatever `workingRecipe`/`isShowingOriginal` currently is,
    /// cancelling/discarding any still-in-flight render for a prior state. `debounced` coalesces a
    /// fast slider drag into a single render instead of one per tick (PHOTO-EDITOR.md § 18.1:
    /// "Hủy render cũ khi có yêu cầu mới"), short enough to still feel "gần liên tục" (§ 18.1).
    private func refreshPreview(debounced: Bool = false) async {
        renderGeneration += 1
        let generation = renderGeneration

        if debounced {
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard generation == renderGeneration else { return }
        }

        let recipe = isShowingOriginal ? .original(photoId: context.photoId, now: session.workingRecipe.createdAt) : session.workingRecipe
        let renderEngine = renderEngine
        let photoId = context.photoId
        let targetSize = Self.previewTargetSize

        let image = await Task<CGImage?, Never> {
            try? await renderEngine.renderPreview(photoId: photoId, recipe: recipe, targetSize: targetSize)
        }.value

        // A newer refresh started while this one was in flight — its result (or failure) is
        // stale and must never overwrite whatever that newer call already produced.
        guard generation == renderGeneration else { return }

        if let image {
            loadState = .loaded(image)
        } else if case .loaded = loadState {
            // A transient failure (e.g. a momentary PHImageManager hiccup) while switching
            // presets/dragging intensity must not blank out an already-good preview with an
            // error screen — only the very first load surfaces `.failed`.
        } else {
            loadState = .failed
        }
    }

    /// ADDEDUM § 11 — renders every preset at its own default intensity from the photo actually
    /// being edited, in parallel, discarding results if a newer batch supersedes this one before
    /// it finishes (e.g. the editor closed mid-render).
    private func loadPresetThumbnails() async {
        guard !presets.isEmpty else { return }
        thumbnailGeneration += 1
        let generation = thumbnailGeneration

        let renderEngine = renderEngine
        let photoId = context.photoId
        let targetSize = Self.presetThumbnailSize
        let presetsSnapshot = presets

        let results = await withTaskGroup(of: (String, CGImage?).self) { group in
            for preset in presetsSnapshot {
                group.addTask {
                    var recipe = PhotoEditRecipe.original(photoId: photoId)
                    recipe.presetId = preset.isOriginal ? nil : preset.id
                    recipe.presetIntensity = preset.isOriginal ? 0 : preset.defaultIntensity
                    let image = try? await renderEngine.renderPreview(photoId: photoId, recipe: recipe, targetSize: targetSize)
                    return (preset.id, image)
                }
            }
            var collected: [(String, CGImage?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        guard generation == thumbnailGeneration else { return }
        for (presetId, image) in results {
            if let image {
                presetThumbnails[presetId] = image
            }
        }
    }

    /// Persists `workingRecipe` for just this photo and returns the result the caller should act
    /// on. Save-scope options ("apply to whole Album/Event") are Bước 8's job — this is always
    /// the "chỉ ảnh này" path.
    @discardableResult
    func save() async -> PhotoEditorResult {
        guard !isSaving else { return .cancelled(photoId: context.photoId) }
        isSaving = true
        defer { isSaving = false }

        var recipe = session.workingRecipe
        recipe.updatedAt = Date()

        do {
            try await repository.saveRecipe(recipe)
            session = PhotoEditSession(photoId: context.photoId, existingRecipe: recipe)
            return PhotoEditorResult(photoId: context.photoId, didSave: true, collectionStyleChanged: false, affectedPhotoIds: [context.photoId])
        } catch {
            NiziLogger.photoEditor.error("photo_editor_save_failed photoId=\(self.context.photoId, privacy: .private) error=\(String(describing: error), privacy: .public)")
            return .cancelled(photoId: context.photoId)
        }
    }

    func discardChanges() -> PhotoEditorResult {
        .cancelled(photoId: context.photoId)
    }
}
