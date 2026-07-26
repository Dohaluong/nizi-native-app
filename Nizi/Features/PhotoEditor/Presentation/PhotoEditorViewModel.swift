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
/// `@MainActor` since every property here drives UI directly; `renderEngine`/`repository` are
/// `Sendable` and do their own actor-hopping internally.
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

    private let renderEngine: PhotoRendering
    private let repository: PhotoEditRepository

    /// Cancels/supersedes any render still in flight when a newer one is requested — see
    /// `refreshPreview()`. A monotonic counter rather than relying solely on `Task` cancellation
    /// propagating through `PhotoRenderEngine`'s own PHImageManager cancellation: it's simpler to
    /// reason about and race-free even if the underlying cancellation is slow or best-effort.
    private var renderGeneration = 0

    /// Matches the existing viewers' `displayPreview` ceiling (`EventDetailView.ImageSizing`) —
    /// deliberately capped well below full device resolution; requesting at full screen
    /// resolution was the documented cause of slow/failed iCloud-backed loads elsewhere in this
    /// app, and there is no reason Photo Editor's own preview would be exempt from that.
    static let previewTargetSize = CGSize(width: 1000, height: 1000)

    init(context: EditorContext, renderEngine: PhotoRendering, repository: PhotoEditRepository) {
        self.context = context
        self.renderEngine = renderEngine
        self.repository = repository
        session = PhotoEditSession(photoId: context.photoId, existingRecipe: nil)
    }

    var hasUnsavedChanges: Bool { session.hasUnsavedChanges }

    /// Loads any previously saved recipe for this photo (so reopening the editor on an
    /// already-edited photo picks up where it left off, § 6.4's "phục hồi trạng thái đã lưu"),
    /// then renders the first preview.
    func loadPreview() async {
        loadState = .loading
        do {
            let existingRecipe = try await repository.getRecipe(photoId: context.photoId)
            session = PhotoEditSession(photoId: context.photoId, existingRecipe: existingRecipe)
        } catch {
            NiziLogger.photoEditor.error("photo_editor_recipe_load_failed photoId=\(self.context.photoId, privacy: .private) error=\(String(describing: error), privacy: .public)")
            loadState = .failed
            return
        }
        await refreshPreview()
    }

    /// The press-and-hold entry point — never mutate `isShowingOriginal` directly, since the
    /// point of holding is that it must actually re-render (Bước 4/5 land presets/adjustments that
    /// make the two renders visibly diverge; Sprint 3 has the plumbing but no filters yet, so both
    /// are still pixel-identical outputs of the same passthrough pipeline).
    func setShowingOriginal(_ showingOriginal: Bool) {
        guard isShowingOriginal != showingOriginal else { return }
        isShowingOriginal = showingOriginal
        Task { await refreshPreview() }
    }

    /// Re-renders the preview for whatever `workingRecipe`/`isShowingOriginal` currently is,
    /// cancelling/discarding any still-in-flight render for a prior state. Bước 5's slider drags
    /// will call this on every value change; this is the cancellation seam PHOTO-EDITOR.md § 18.1
    /// ("Hủy render cũ khi có yêu cầu mới") asks for, built now so later sprints don't need to
    /// revisit it.
    private func refreshPreview() async {
        renderGeneration += 1
        let generation = renderGeneration

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
        } else {
            loadState = .failed
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
