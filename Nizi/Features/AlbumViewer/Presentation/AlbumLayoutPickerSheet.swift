//
//  AlbumLayoutPickerSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Only offers layouts whose slot count matches the Page's current photo count (docs/specs/
/// SPEC-REAL-ALBUM.md § 20.1) and renders every candidate with the Page's *real* photos, not
/// just a name (§ 20.3). This is a preview-only remap (simple slot-order zip) — the real,
/// orientation/importance-aware reassignment happens in `AlbumEditActionApplying` once the user
/// actually confirms a choice.
struct AlbumLayoutPickerSheet: View {
    let page: AlbumDraftPage
    let layoutRepository: AlbumLayoutRepository
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var candidateLayouts: [AlbumPageLayout] {
        (try? layoutRepository.layouts(photoCount: page.assignments.count, format: page.format))?.sorted { $0.id < $1.id } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 16) {
                    ForEach(candidateLayouts) { layout in
                        Button {
                            onSelect(layout.id)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                AlbumPageRenderer(
                                    layout: layout, assignments: previewAssignments(for: layout),
                                    photoProvider: ProductionAlbumSlotPhotoProvider()
                                )
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    if layout.id == page.layoutId {
                                        RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3)
                                    }
                                }
                                Text(localizedString(dynamicKey: layout.nameKey, defaultValue: layout.name))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("album.changeLayout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel") { dismiss() }
                }
            }
        }
    }

    private func previewAssignments(for layout: AlbumPageLayout) -> [AlbumPhotoAssignment] {
        let sortedSlots = layout.slots.sorted { $0.order < $1.order }
        return zip(sortedSlots, page.assignments).map { slot, assignment in
            AlbumPhotoAssignment(id: "preview-\(slot.id)", slotId: slot.id, photo: assignment.photo, crop: .centered)
        }
    }
}
