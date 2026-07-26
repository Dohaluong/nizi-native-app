//
//  SaveScopeSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// The save-scope bottom sheet (PHOTO-EDITOR.md § 11.2/§ 11.4) — only ever presented when Photo
/// Editor was opened from an Album or Event (§ 4.3: a standalone edit has no scope choice at all).
/// Two steps in one view: the initial choice, then (only if "apply to whole" is picked) a
/// confirmation showing exactly what will be applied, with the optional per-photo Auto Enhance
/// toggle (§ 11.5).
struct SaveScopeSheet: View {
    let sourceType: EditorSourceType
    let presetName: String
    let presetIntensityPercent: Int
    let onSaveThisPhotoOnly: (_ overwrite: Bool) -> Void
    let onApplyToWholeCollection: (_ overwrite: Bool, _ autoEnhanceEachPhoto: Bool) -> Void
    let onCancel: () -> Void

    @State private var isShowingWholeCollectionConfirmation = false
    @State private var autoEnhanceEachPhoto = false
    /// Defaults to "save as copy" (`false`) — the non-destructive, easily-reversible choice. Photo
    /// Editor's own edits are always non-destructive right up until this exact moment; overwriting
    /// is the one action here that deletes something real from the user's library, so it should
    /// never be the silent default.
    @State private var overwriteOriginal = false

    var body: some View {
        if isShowingWholeCollectionConfirmation {
            confirmationStep
        } else {
            choiceStep
        }
    }

    private var choiceStep: some View {
        VStack(spacing: 14) {
            Text("photoEditor.saveScope.title")
                .font(.headline)

            assetHandlingPicker

            Button {
                onSaveThisPhotoOnly(overwriteOriginal)
            } label: {
                Text("photoEditor.saveScope.thisPhotoOnly")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                isShowingWholeCollectionConfirmation = true
            } label: {
                wholeCollectionLabel
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("common.action.cancel", role: .cancel) {
                onCancel()
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }

    /// § — new "Lưu đè / Tạo bản copy" choice: saving now always writes the currently-edited photo
    /// as a brand-new asset (preserving EXIF) rather than just a recipe, so the user needs to say
    /// up front whether the original asset should be deleted afterward or kept alongside the new
    /// one. Shown once, above both save-scope buttons, since it applies the same way regardless of
    /// "this photo only" vs "whole collection."
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

    @ViewBuilder
    private var wholeCollectionLabel: some View {
        switch sourceType {
        case .album:
            Text("photoEditor.saveScope.applyToAlbum")
        case .event:
            Text("photoEditor.saveScope.applyToEvent")
        case .standalone:
            EmptyView() // never reached — this sheet is never presented for `.standalone`.
        }
    }

    private var confirmationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            confirmationTitle
                .font(.headline)

            LabeledContent("photoEditor.tool.preset", value: presetName)
            LabeledContent("photoEditor.preset.intensity", value: "\(presetIntensityPercent)%")

            Text("photoEditor.saveScope.adjustNotCopiedNotice")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("photoEditor.saveScope.autoEnhanceEachPhoto", isOn: $autoEnhanceEachPhoto)

            HStack {
                Button("common.action.cancel") {
                    isShowingWholeCollectionConfirmation = false
                }
                Spacer()
                Button("photoEditor.autoEnhance.apply") {
                    onApplyToWholeCollection(overwriteOriginal, autoEnhanceEachPhoto)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var confirmationTitle: some View {
        switch sourceType {
        case .album:
            Text("photoEditor.saveScope.confirmApplyToAlbum")
        case .event:
            Text("photoEditor.saveScope.confirmApplyToEvent")
        case .standalone:
            EmptyView()
        }
    }
}
