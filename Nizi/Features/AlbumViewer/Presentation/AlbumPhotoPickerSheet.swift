//
//  AlbumPhotoPickerSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// "Change Cover" picker — only ever shows photos already in the Album, never re-opens the
/// Event or Photos Library (docs/specs/SPEC-REAL-ALBUM.md § 19.1).
struct AlbumPhotoPickerSheet: View {
    let draft: AlbumDraft
    let title: LocalizedStringKey
    let onSelect: (AlbumPhotoReference) -> Void

    @Environment(\.dismiss) private var dismiss

    private var references: [AlbumPhotoReference] {
        var seen = Set<String>()
        var result: [AlbumPhotoReference] = []
        for spread in draft.spreads {
            for page in [spread.leftPage, spread.rightPage] {
                for assignment in page.assignments where seen.insert(assignment.photo.id).inserted {
                    result.append(assignment.photo)
                }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 4)], spacing: 4) {
                    ForEach(references, id: \.id) { reference in
                        Button {
                            onSelect(reference)
                        } label: {
                            AlbumPhotoView(reference: reference, crop: .centered, contentMode: .fill, targetSize: nil)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel") { dismiss() }
                }
            }
        }
    }
}
