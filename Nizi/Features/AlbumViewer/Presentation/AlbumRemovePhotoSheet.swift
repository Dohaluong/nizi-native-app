//
//  AlbumRemovePhotoSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Pick which photo on the current Page to remove. `AlbumEditActionApplying` is what actually
/// blocks removing a Page's last photo (docs/specs/SPEC-REAL-ALBUM.md § 22.2) — this sheet just
/// lets the user pick a target.
struct AlbumRemovePhotoSheet: View {
    let page: AlbumDraftPage
    let onRemove: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 4)], spacing: 4) {
                    ForEach(page.assignments) { assignment in
                        Button {
                            onRemove(assignment.slotId)
                            dismiss()
                        } label: {
                            AlbumPhotoView(reference: assignment.photo, crop: .centered, contentMode: .fill, targetSize: nil)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("album.removePhoto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel") { dismiss() }
                }
            }
        }
    }
}
