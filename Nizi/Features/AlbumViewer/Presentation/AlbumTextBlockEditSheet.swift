//
//  AlbumTextBlockEditSheet.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// Bundles which Page/text block a tap targeted, plus its current (effective) style — mirrors
/// `AlbumPhotoCropTarget`'s own shape/purpose. Built directly from `AlbumPageRenderer.
/// onTapTextBlock`'s own "effective assignment" (real if this Page has one, else synthesized from
/// the layout block's default), so every field here already reflects whatever is actually on
/// screen right now.
struct AlbumTextBlockEditTarget: Identifiable {
    let pageId: String
    let textBlockId: String
    let currentText: String
    let currentHorizontalAlignment: AlbumTextHorizontalAlignment
    let currentVerticalAlignment: AlbumTextVerticalAlignment
    let currentFontFamily: AlbumTextFontFamily
    let currentFontSize: Double
    let currentFontWeight: AlbumTextFontWeight
    var id: String { "\(pageId)-\(textBlockId)" }
}

/// § user request — "Chưa tap vào chữ để sửa nội dung chữ được" + "cho phép chọn cỡ chữ, font,
/// weight, căn lề ... trong modal editor này". A plain `TextEditor`, not a pinch/pan canvas like
/// `AlbumPhotoCropSheet` — nothing here has that screen's drag-vs-dismiss conflict (scrolling a
/// `TextEditor` while a sheet's own interactive-dismiss is active is completely standard, expected
/// behavior everywhere in iOS), so this stays a `.sheet` rather than a pushed screen.
struct AlbumTextBlockEditSheet: View {
    let onSave: (
        _ text: String, _ horizontalAlignment: AlbumTextHorizontalAlignment, _ verticalAlignment: AlbumTextVerticalAlignment,
        _ fontFamily: AlbumTextFontFamily, _ fontSize: Double, _ fontWeight: AlbumTextFontWeight
    ) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var horizontalAlignment: AlbumTextHorizontalAlignment
    @State private var verticalAlignment: AlbumTextVerticalAlignment
    @State private var fontFamily: AlbumTextFontFamily
    @State private var fontSize: Double
    @State private var fontWeight: AlbumTextFontWeight
    // § user report — "không có con trỏ ... không biết viết gì ở đâu": auto-focusing the moment
    // this sheet appears means the keyboard is already up and the cursor already blinking, so
    // there's no ambiguity about where to type.
    @FocusState private var isTextEditorFocused: Bool

    init(
        target: AlbumTextBlockEditTarget,
        onSave: @escaping (
            _ text: String, _ horizontalAlignment: AlbumTextHorizontalAlignment, _ verticalAlignment: AlbumTextVerticalAlignment,
            _ fontFamily: AlbumTextFontFamily, _ fontSize: Double, _ fontWeight: AlbumTextFontWeight
        ) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: target.currentText)
        _horizontalAlignment = State(initialValue: target.currentHorizontalAlignment)
        _verticalAlignment = State(initialValue: target.currentVerticalAlignment)
        _fontFamily = State(initialValue: target.currentFontFamily)
        _fontSize = State(initialValue: target.currentFontSize)
        _fontWeight = State(initialValue: target.currentFontWeight)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("album.textBlock.edit.content_section") {
                    textEditorField
                }

                Section("album.textBlock.edit.alignment_section") {
                    Picker("album.textBlock.edit.horizontal_alignment", selection: $horizontalAlignment) {
                        ForEach(AlbumTextHorizontalAlignment.allCases, id: \.self) { alignment in
                            Text(Self.displayName(for: alignment)).tag(alignment)
                        }
                    }
                    Picker("album.textBlock.edit.vertical_alignment", selection: $verticalAlignment) {
                        ForEach(AlbumTextVerticalAlignment.allCases, id: \.self) { alignment in
                            Text(Self.displayName(for: alignment)).tag(alignment)
                        }
                    }
                }

                Section("album.textBlock.edit.style_section") {
                    Picker("album.textBlock.edit.font_family", selection: $fontFamily) {
                        ForEach(AlbumTextFontFamily.allCases, id: \.self) { family in
                            Text(family.rawValue).tag(family)
                        }
                    }
                    Picker("album.textBlock.edit.font_weight", selection: $fontWeight) {
                        ForEach(AlbumTextFontWeight.allCases, id: \.self) { weight in
                            Text(Self.displayName(for: weight)).tag(weight)
                        }
                    }
                    Stepper(value: $fontSize, in: 8...200, step: 2) {
                        HStack {
                            Text("album.textBlock.edit.font_size")
                            Spacer()
                            Text("\(Int(fontSize))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("album.textBlock.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("album.textBlock.edit.done") {
                        onSave(text, horizontalAlignment, verticalAlignment, fontFamily, fontSize, fontWeight)
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { isTextEditorFocused = true }
        }
    }

    // § user report — "hiện giờ toàn 1 màu trắng, không có con trỏ, không có placeholder nên
    // không biết viết gì ở đâu": a bare `TextEditor` has no border/background of its own to read
    // as "this is an input field," and (unlike `TextField`) no built-in placeholder support at
    // all. Gives it an explicit bordered box, layers a placeholder `Text` *behind* it (visible only
    // while `text` is empty — `.scrollContentBackground(.hidden)` is what lets that show through,
    // since `TextEditor` otherwise paints its own opaque background over it), and auto-focuses so
    // the cursor is already visible the moment this sheet opens.
    private var textEditorField: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(localizedString("album.textBlock.edit.placeholder", defaultValue: "Enter text"))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($isTextEditorFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(.separator), lineWidth: 1))
    }

    private static func displayName(for alignment: AlbumTextHorizontalAlignment) -> String {
        switch alignment {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    private static func displayName(for alignment: AlbumTextVerticalAlignment) -> String {
        switch alignment {
        case .top: return "Top"
        case .center: return "Center"
        case .bottom: return "Bottom"
        }
    }

    private static func displayName(for weight: AlbumTextFontWeight) -> String {
        switch weight {
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        }
    }
}
