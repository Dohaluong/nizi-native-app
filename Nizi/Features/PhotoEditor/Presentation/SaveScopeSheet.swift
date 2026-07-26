//
//  SaveScopeSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// The save-scope choice (PHOTO-EDITOR.md § 11.2) — only ever presented when Photo Editor was
/// opened from an Album or Event (§ 4.3: a standalone edit has no scope choice at all). Presented
/// by `PhotoEditorView` as a small, centered modal card sized to fit its own content (never a
/// bottom sheet) — this view has no opinion on its own presentation chrome, just its content.
///
/// Only ever saves this one photo (as a brand-new asset, § 11.3) — there is no "apply this style
/// to the whole Album/Event" option here; that whole-collection flow was removed because it added
/// a second confirmation step and an Auto Enhance toggle for a use case that wasn't earning its
/// keep. `presetName`/`presetIntensityPercent` are unused now that the confirmation step showing
/// them is gone but are kept as parameters so the caller doesn't need its own conditional wiring —
/// harmless to keep passing.
struct SaveScopeSheet: View {
    let sourceType: EditorSourceType
    let presetName: String
    let presetIntensityPercent: Int
    let onSaveThisPhotoOnly: (_ overwrite: Bool) -> Void
    let onCancel: () -> Void

    /// Defaults to "save as copy" (`false`) — the non-destructive, easily-reversible choice. Photo
    /// Editor's own edits are always non-destructive right up until this exact moment; overwriting
    /// is the one action here that deletes something real from the user's library, so it should
    /// never be the silent default.
    @State private var overwriteOriginal = false

    var body: some View {
        VStack(spacing: 14) {
            Text("photoEditor.saveScope.title")
                .font(.headline)

            assetHandlingPicker

            Button {
                onSaveThisPhotoOnly(overwriteOriginal)
            } label: {
                Text("album.save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("common.action.cancel", role: .cancel) {
                onCancel()
            }
        }
        .padding(20)
    }

    /// § — "Lưu đè / Tạo bản copy" choice: saving now always writes the currently-edited photo as
    /// a brand-new asset (preserving EXIF) rather than just a recipe, so the user needs to say up
    /// front whether the original asset should be deleted afterward or kept alongside the new one.
    private var assetHandlingPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("photoEditor.saveScope.assetHandling", selection: $overwriteOriginal) {
                Text("photoEditor.saveScope.saveAsCopy").tag(false)
                Text("photoEditor.saveScope.overwrite").tag(true)
            }
            .pickerStyle(.segmented)

            if overwriteOriginal {
                Text("photoEditor.saveScope.overwriteWarning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
