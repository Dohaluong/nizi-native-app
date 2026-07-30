//
//  AlbumTextBlockEditSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// Bundles which Page/text block a tap targeted, plus its current content — mirrors
/// `AlbumPhotoCropTarget`'s own shape/purpose.
struct AlbumTextBlockEditTarget: Identifiable {
    let pageId: String
    let textBlockId: String
    let currentText: String
    var id: String { "\(pageId)-\(textBlockId)" }
}

/// § user request — "Chưa tap vào chữ để sửa nội dung chữ được": quick-tap a text block (see
/// `AlbumPageRenderer.onTapTextBlock`) opens this. A plain `TextEditor`, not a pinch/pan canvas
/// like `AlbumPhotoCropSheet` — nothing here has that screen's drag-vs-dismiss conflict (scrolling
/// a `TextEditor` while a sheet's own interactive-dismiss is active is completely standard,
/// expected behavior everywhere in iOS), so this stays a `.sheet` rather than a pushed screen.
struct AlbumTextBlockEditSheet: View {
    let initialText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(initialText: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(12)
                .navigationTitle("album.textBlock.edit.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.action.cancel") { onCancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("album.textBlock.edit.done") { onSave(text) }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}
