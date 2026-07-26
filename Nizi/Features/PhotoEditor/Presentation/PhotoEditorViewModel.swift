//
//  PhotoEditorViewModel.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Observation

/// What's currently on screen for the photo being edited. Not `Equatable` on the image itself
/// beyond reference identity — two `.loaded` states are only ever compared to detect "has the
/// underlying `PlatformImage` instance changed," never for value equality of pixels.
enum PhotoEditorLoadState: Equatable {
    case loading
    case loaded(PlatformImage)
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
/// from the View, and because later sprints (render debouncing, preset thumbnail generation,
/// Auto Enhance) need a place to own long-lived `Task`s that must outlive any single SwiftUI page
/// being recycled — the same lesson `CurationPreviewView` already learned the hard way for its own
/// image-loading tasks (see docs/modules/PHOTO-EDITOR-IMPLEMENTATION-PLAN.md § 1.5, § 7).
///
/// `@MainActor` since every property here drives UI directly; the `imageLoader`/`repository`
/// dependencies are `Sendable` and do their own actor-hopping internally.
@MainActor
@Observable
final class PhotoEditorViewModel {
    let context: EditorContext

    private(set) var session: PhotoEditSession
    private(set) var loadState: PhotoEditorLoadState = .loading
    private(set) var isSaving = false
    /// Toggled by the press-and-hold gesture in `PhotoEditorView`. Sprint 2 has no render engine
    /// yet, so `displayedImage` returns the same loaded preview regardless of this flag — Bước 3
    /// is what makes holding actually reveal a different (unedited) image.
    var isShowingOriginal = false

    private let imageLoader: PhotoEditorImageLoading
    private let repository: PhotoEditRepository

    /// Matches the existing viewers' `displayPreview` ceiling (`EventDetailView.ImageSizing`) —
    /// deliberately capped well below full device resolution; requesting at full screen
    /// resolution was the documented cause of slow/failed iCloud-backed loads elsewhere in this
    /// app, and there is no reason Photo Editor's own preview would be exempt from that.
    static let previewTargetSize = CGSize(width: 1000, height: 1000)

    init(context: EditorContext, imageLoader: PhotoEditorImageLoading, repository: PhotoEditRepository) {
        self.context = context
        self.imageLoader = imageLoader
        self.repository = repository
        session = PhotoEditSession(photoId: context.photoId, existingRecipe: nil)
    }

    var hasUnsavedChanges: Bool { session.hasUnsavedChanges }

    /// The image `PhotoEditorView` should currently show. `nil` while loading or on failure — the
    /// View is responsible for its own loading/failure UI in those states.
    var displayedImage: PlatformImage? {
        guard case let .loaded(image) = loadState else { return nil }
        return image
    }

    /// Loads (or reloads, e.g. after a failed attempt) the preview and restores any previously
    /// saved recipe for this photo, so reopening the editor on an already-edited photo picks up
    /// where it left off (§ 6.4's "phục hồi trạng thái đã lưu").
    func loadPreview() async {
        loadState = .loading
        do {
            async let recipeLookup = repository.getRecipe(photoId: context.photoId)
            async let imageLookup = imageLoader.loadPreview(photoId: context.photoId, targetSize: Self.previewTargetSize)

            let (existingRecipe, image) = try await (recipeLookup, imageLookup)
            session = PhotoEditSession(photoId: context.photoId, existingRecipe: existingRecipe)
            loadState = .loaded(image)
        } catch {
            NiziLogger.photoEditor.error("photo_editor_load_failed photoId=\(self.context.photoId, privacy: .private) error=\(String(describing: error), privacy: .public)")
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
