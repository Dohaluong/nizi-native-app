//
//  AlbumInfoEditSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Edits the Album's own metadata (title, subtitle, place, date range, cover photo) — separate
/// from `AlbumPageViewer`'s Page-content editing (layout/photos/spreads). Reached from
/// `AlbumDetailView`'s hero "…" menu.
struct AlbumInfoEditSheet: View {
    let draft: AlbumDraft
    let onSave: (AlbumDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var subtitle: String
    @State private var placeName: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var coverPhotoId: String
    @State private var isChangingCover = false
    @State private var isSaving = false

    init(draft: AlbumDraft, onSave: @escaping (AlbumDraft) async -> Void) {
        self.draft = draft
        self.onSave = onSave
        _title = State(initialValue: draft.title)
        _subtitle = State(initialValue: draft.subtitle ?? "")
        _placeName = State(initialValue: draft.primaryLocationName ?? draft.primaryPlace?.displayName ?? "")
        _startDate = State(initialValue: draft.startDate ?? draft.createdAt)
        _endDate = State(initialValue: draft.endDate ?? draft.startDate ?? draft.createdAt)
        _coverPhotoId = State(initialValue: draft.coverPhotoId)
    }

    private var coverPhotoReference: AlbumPhotoReference {
        AlbumPhotoReference(id: coverPhotoId, source: .applePhotos, sourceIdentifier: coverPhotoId, originalFilename: nil)
    }

    private var isTitleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("album.edit.info.cover_section") {
                    Button {
                        isChangingCover = true
                    } label: {
                        HStack(spacing: 14) {
                            AlbumPhotoView(reference: coverPhotoReference, crop: .centered, contentMode: .fill, targetSize: CGSize(width: 160, height: 160))
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("album.changeCover")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("album.edit.info.details_section") {
                    TextField("album.edit.info.title_placeholder", text: $title)
                    TextField("album.edit.info.subtitle_placeholder", text: $subtitle)
                    TextField("album.edit.info.place_placeholder", text: $placeName)
                }

                Section("album.edit.info.date_section") {
                    DatePicker("album.edit.info.start_date", selection: $startDate, displayedComponents: .date)
                    DatePicker("album.edit.info.end_date", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
            }
            .navigationTitle("album.edit.info.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("album.save") { Task { await save() } }
                        .disabled(!isTitleValid || isSaving)
                }
            }
            .sheet(isPresented: $isChangingCover) {
                AlbumPhotoPickerSheet(draft: draft, title: "album.changeCover") { reference in
                    coverPhotoId = reference.id
                    isChangingCover = false
                }
                .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = draft
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.subtitle = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
        let trimmedPlace = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.primaryLocationName = trimmedPlace.isEmpty ? nil : trimmedPlace
        updated.startDate = startDate
        updated.endDate = max(startDate, endDate)
        updated.coverPhotoId = coverPhotoId
        updated.updatedAt = Date()
        await onSave(updated)
        dismiss()
    }
}
