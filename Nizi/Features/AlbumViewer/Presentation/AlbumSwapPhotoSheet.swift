//
//  AlbumSwapPhotoSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Swap within the current Page, or with the facing Page in the same Spread — resolved through
/// `spreadId`/`positionInSpread`, never by showing two Pages at once (docs/specs/ADDENDUM-001.md
/// § 15, § 19). Tap one photo, then a second; the two swap.
struct AlbumSwapPhotoSheet: View {
    let currentPage: AlbumViewerPage
    let draft: AlbumDraft
    let onSwap: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var firstSelection: String?

    private var facingPage: AlbumDraftPage? {
        guard let spread = draft.spreads.first(where: { $0.id == currentPage.spreadId }) else { return nil }
        return currentPage.positionInSpread == .left ? spread.rightPage : spread.leftPage
    }

    var body: some View {
        NavigationStack {
            List {
                Section("album.edit.swap_this_page") {
                    grid(for: currentPage.page.assignments)
                }
                if let facingPage {
                    Section("album.edit.swap_facing_page") {
                        grid(for: facingPage.assignments)
                    }
                }
            }
            .navigationTitle("album.edit.choose_photo_to_swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel") { dismiss() }
                }
            }
        }
    }

    private func grid(for assignments: [AlbumPhotoAssignment]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], spacing: 4) {
            ForEach(assignments) { assignment in
                Button {
                    select(assignment.id)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        AlbumPhotoView(reference: assignment.photo, crop: .centered, contentMode: .fill, targetSize: nil)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        if firstSelection == assignment.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listRowInsets(EdgeInsets())
        .padding(4)
    }

    private func select(_ assignmentId: String) {
        if let firstSelection, firstSelection != assignmentId {
            onSwap(firstSelection, assignmentId)
            dismiss()
        } else {
            firstSelection = assignmentId
        }
    }
}
