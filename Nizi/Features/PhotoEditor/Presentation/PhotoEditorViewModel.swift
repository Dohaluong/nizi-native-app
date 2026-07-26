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

    private(set) var isAutoEnhanceRunning = false
    /// Snapshot taken right before Auto Enhance overwrites `adjustments` — the one-level undo
    /// § 9.3 asks for. `nil` whenever there's nothing to undo (never run yet, or already undone).
    private var adjustmentsBeforeAutoEnhance: PhotoAdjustments?

    /// This photo's Album/Event style, fetched once at `loadPreview()` — `nil` for `.standalone`
    /// or a collection that has no style saved yet. Exposed (read-only) so the Preset tab can show
    /// "inheriting the Album/Event style" (§ 12.3) when relevant.
    private(set) var collectionStyle: CollectionEditStyle?

    private let renderEngine: PhotoRendering
    private let repository: PhotoEditRepository
    private let presetRepository: PresetRepository
    private let autoEnhanceService: AutoEnhancing
    private let collectionStyleRepository: CollectionStyleRepository
    private let assetExporter: PhotoAssetExporting

    /// Cancels/supersedes any preview render still in flight when a newer one is requested — see
    /// `refreshPreview()`. A monotonic counter rather than relying solely on `Task` cancellation
    /// propagating through `PhotoRenderEngine`'s own PHImageManager cancellation: it's simpler to
    /// reason about and race-free even if the underlying cancellation is slow or best-effort.
    private var renderGeneration = 0

    /// Matches the existing viewers' `displayPreview` ceiling (`EventDetailView.ImageSizing`) —
    /// deliberately capped well below full device resolution; requesting at full screen
    /// resolution was the documented cause of slow/failed iCloud-backed loads elsewhere in this
    /// app, and there is no reason Photo Editor's own preview would be exempt from that.
    static let previewTargetSize = CGSize(width: 1000, height: 1000)

    init(
        context: EditorContext,
        renderEngine: PhotoRendering,
        repository: PhotoEditRepository,
        presetRepository: PresetRepository,
        autoEnhanceService: AutoEnhancing,
        collectionStyleRepository: CollectionStyleRepository,
        assetExporter: PhotoAssetExporting = PhotoAssetExporter()
    ) {
        self.context = context
        self.renderEngine = renderEngine
        self.repository = repository
        self.presetRepository = presetRepository
        self.autoEnhanceService = autoEnhanceService
        self.collectionStyleRepository = collectionStyleRepository
        self.assetExporter = assetExporter
        session = PhotoEditSession(photoId: context.photoId, existingRecipe: nil)
    }

    var hasUnsavedChanges: Bool { session.hasUnsavedChanges }

    /// Whether the Auto Enhance tab should offer "Undo" right now — § 9.3 requires this to always
    /// be possible right after applying, never a one-shot irreversible action.
    var canUndoAutoEnhance: Bool { adjustmentsBeforeAutoEnhance != nil }

    /// `nil` `presetId` displays as Original — never a separate "no selection" state (spec § 7.4:
    /// Original is always a real, selectable entry, not the absence of one).
    var selectedPresetId: String { session.workingRecipe.presetId ?? PresetDefinition.originalId }

    /// § 12.3 — true while this photo's current preset/intensity still match its Album/Event's
    /// style exactly (whether because the user hasn't touched Preset at all, or changed it back
    /// to match). Becomes false the moment the two diverge, which is what `saveThisPhotoOnly()`
    /// uses to decide whether this save is a real photo override (§ 12.4).
    var isInheritingCollectionStyle: Bool {
        guard let collectionStyle else { return false }
        return session.workingRecipe.presetId == collectionStyle.presetId
            && session.workingRecipe.presetIntensity == collectionStyle.presetIntensity
    }

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
    /// resolves this photo's Album/Event style if it belongs to one, then renders the first
    /// preview.
    func loadPreview() async {
        loadState = .loading
        presets = (try? presetRepository.loadPresets()) ?? []

        if let sourceId = context.sourceId, context.sourceType != .standalone {
            let collectionType: CollectionType = context.sourceType == .album ? .album : .event
            collectionStyle = try? await collectionStyleRepository.getStyle(type: collectionType, id: sourceId)
        }

        do {
            let existingRecipe = try await repository.getRecipe(photoId: context.photoId)
            if let existingRecipe {
                session = PhotoEditSession(photoId: context.photoId, existingRecipe: existingRecipe)
            } else if let collectionStyle {
                // § 12.3 — "Ảnh A: Dùng style của Album": a photo with no recipe of its own opens
                // already showing whatever the collection currently specifies, not a blank
                // Original — `CollectionStyleResolver` resolves this the same way a future
                // display pipeline would, so the editor and that pipeline never disagree.
                let inherited = CollectionStyleResolver.resolvedRecipe(photoId: context.photoId, photoRecipe: nil, collectionStyle: collectionStyle)
                session = PhotoEditSession(photoId: context.photoId, existingRecipe: inherited)
            } else {
                session = PhotoEditSession(photoId: context.photoId, existingRecipe: nil)
            }
        } catch {
            NiziLogger.photoEditor.error("photo_editor_recipe_load_failed photoId=\(self.context.photoId, privacy: .private) error=\(String(describing: error), privacy: .public)")
            loadState = .failed
            return
        }

        await refreshPreview()
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

    // MARK: - Adjust (Bước 5)

    /// UI-facing `-100...+100` for one Adjust slider; the engine's own storage
    /// (`PhotoAdjustments`) stays `-1...+1` (§ 8.3). Setting triggers a debounced re-render, same
    /// as `presetIntensityPercent`.
    func adjustPercent(for parameter: AdjustParameter) -> Double {
        Double(parameter.value(in: session.workingRecipe.adjustments)) * 100
    }

    func setAdjustPercent(_ parameter: AdjustParameter, _ percent: Double) {
        let clamped = min(max(percent, -100), 100)
        parameter.setting(Float(clamped / 100), in: &session.workingRecipe.adjustments)
        Task { await refreshPreview(debounced: true) }
    }

    /// § 8.4 — "Đặt lại thông số hiện tại": clears just the one field, leaves every other
    /// Adjust value and the current preset untouched.
    func resetAdjustParameter(_ parameter: AdjustParameter) {
        parameter.setting(0, in: &session.workingRecipe.adjustments)
        Task { await refreshPreview() }
    }

    /// § 8.4 — "Đặt lại toàn bộ Adjust": all six sliders back to zero, preset untouched.
    func resetAllAdjustments() {
        session.workingRecipe.adjustments = .identity
        Task { await refreshPreview() }
    }

    /// § 8.4 / § 16.2 — "Đặt lại toàn bộ ảnh về Original": preset, intensity, and every Adjust
    /// value all clear at once. Still just the in-session `workingRecipe` — Cancel would still
    /// restore whatever this photo had before the editor opened.
    func resetEntirePhoto() {
        session.resetToOriginal()
        Task { await refreshPreview() }
    }

    // MARK: - Auto Enhance (Bước 6)

    /// Analyzes this photo on-device and overwrites `adjustments` with the suggestion — never
    /// merged/blended with whatever Adjust values were already there, so the result is exactly
    /// what `AutoEnhanceRules` computed, visible and editable in the Adjust tab (§ 9.3). Snapshots
    /// the prior `adjustments` first so `undoAutoEnhance()` can restore them exactly.
    func applyAutoEnhance() async {
        guard !isAutoEnhanceRunning else { return }
        isAutoEnhanceRunning = true
        defer { isAutoEnhanceRunning = false }

        do {
            let suggested = try await autoEnhanceService.analyze(photoId: context.photoId)
            adjustmentsBeforeAutoEnhance = session.workingRecipe.adjustments
            session.workingRecipe.adjustments = suggested
            session.workingRecipe.autoEnhanceApplied = true
            session.workingRecipe.autoEnhanceVersion = AutoEnhanceRules.version
            await refreshPreview()
        } catch {
            NiziLogger.photoEditor.error("photo_editor_auto_enhance_failed photoId=\(self.context.photoId, privacy: .private) error=\(String(describing: error), privacy: .public)")
        }
    }

    /// § 9.3 — restores whatever `adjustments` were before Auto Enhance ran, not a blanket reset
    /// to zero (the user may have had manual Adjust values already, which Auto Enhance overwrote).
    func undoAutoEnhance() {
        guard let previous = adjustmentsBeforeAutoEnhance else { return }
        session.workingRecipe.adjustments = previous
        session.workingRecipe.autoEnhanceApplied = false
        session.workingRecipe.autoEnhanceVersion = nil
        adjustmentsBeforeAutoEnhance = nil
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

    // MARK: - Save (Bước 8)

    /// Persists `workingRecipe` for just this photo only — § 11.3's "Chỉ ảnh này" path, and the
    /// only path available at all when `context.sourceType == .standalone` (§ 4.3: no save-scope
    /// choice outside Album/Event).
    @discardableResult
    func saveThisPhotoOnly() async -> PhotoEditorResult {
        guard !isSaving else { return .cancelled(photoId: context.photoId) }
        isSaving = true
        defer { isSaving = false }

        var recipe = session.workingRecipe
        recipe.updatedAt = Date()
        // § 12.4 — a save whose preset/intensity still match the collection's style is still
        // inheriting; one that doesn't (including an explicit reset to Original while a style
        // exists) is a real photo override from this point on.
        recipe.inheritsCollectionStyle = isInheritingCollectionStyle || collectionStyle == nil

        do {
            try await repository.saveRecipe(recipe)
            session = PhotoEditSession(photoId: context.photoId, existingRecipe: recipe)
            return PhotoEditorResult(photoId: context.photoId, didSave: true, collectionStyleChanged: false, affectedPhotoIds: [context.photoId])
        } catch {
            NiziLogger.photoEditor.error("photo_editor_save_failed photoId=\(self.context.photoId, privacy: .private) error=\(String(describing: error), privacy: .public)")
            return .cancelled(photoId: context.photoId)
        }
    }

    /// Album/Event's "save as a real photo" flow — renders this photo's current edit at full
    /// resolution, writes it as a brand-new asset via `assetExporter` (EXIF preserved, dated/
    /// located to match the original), and reports the new asset's id back via
    /// `PhotoEditorResult.newPhotoId` so the caller can swap its own Album-assignment/Event-
    /// curation-item reference over to it. `overwrite` also deletes the original asset once the
    /// new one exists; "save as copy" leaves the original in the library, just no longer
    /// referenced by this Album/Event. Never used for `.standalone` — nothing to swap a reference
    /// in there, so it stays on the plain recipe-only `saveThisPhotoOnly()`.
    @discardableResult
    func saveAsNewAsset(overwrite: Bool) async -> PhotoEditorResult {
        guard !isSaving else { return .cancelled(photoId: context.photoId) }
        isSaving = true
        defer { isSaving = false }

        do {
            let newPhotoId = try await assetExporter.exportEditedCopy(
                photoId: context.photoId,
                recipe: session.workingRecipe,
                renderer: renderEngine,
                deleteOriginal: overwrite
            )
            if overwrite {
                // The original asset is gone — its recipe row would just be an orphan otherwise.
                // The new asset needs none: its pixels already *are* the edited result.
                try? await repository.deleteRecipe(photoId: context.photoId)
            }
            return PhotoEditorResult(
                photoId: context.photoId, didSave: true, collectionStyleChanged: false,
                affectedPhotoIds: [context.photoId], newPhotoId: newPhotoId, didDeleteOriginalAsset: overwrite
            )
        } catch {
            NiziLogger.photoEditor.error("photo_editor_save_as_new_asset_failed photoId=\(self.context.photoId, privacy: .private) error=\(String(describing: error), privacy: .public)")
            return .cancelled(photoId: context.photoId)
        }
    }

    func discardChanges() -> PhotoEditorResult {
        .cancelled(photoId: context.photoId)
    }
}
