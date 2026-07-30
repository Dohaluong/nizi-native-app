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
    let currentFontStyle: AlbumTextFontStyle
    var id: String { "\(pageId)-\(textBlockId)" }
}

/// § user request — "Chưa tap vào chữ để sửa nội dung chữ được" + "cho phép chọn cỡ chữ, font,
/// weight, căn lề ... trong modal editor này" + "Cần có phần Preview ở phía trên cùng editor". A
/// plain `TextEditor`, not a pinch/pan canvas like `AlbumPhotoCropSheet` — nothing here has that
/// screen's drag-vs-dismiss conflict (scrolling a `TextEditor` while a sheet's own
/// interactive-dismiss is active is completely standard, expected behavior everywhere in iOS), so
/// this stays a `.sheet` rather than a pushed screen.
struct AlbumTextBlockEditSheet: View {
    let onSave: (
        _ text: String, _ horizontalAlignment: AlbumTextHorizontalAlignment, _ verticalAlignment: AlbumTextVerticalAlignment,
        _ fontFamily: AlbumTextFontFamily, _ fontSize: Double, _ fontStyle: AlbumTextFontStyle
    ) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var horizontalAlignment: AlbumTextHorizontalAlignment
    @State private var verticalAlignment: AlbumTextVerticalAlignment
    @State private var fontFamily: AlbumTextFontFamily
    @State private var fontSize: Double
    @State private var fontStyle: AlbumTextFontStyle
    // § user report — "không có con trỏ ... không biết viết gì ở đâu": auto-focusing the moment
    // this sheet appears means the keyboard is already up and the cursor already blinking, so
    // there's no ambiguity about where to type.
    @FocusState private var isTextEditorFocused: Bool

    init(
        target: AlbumTextBlockEditTarget,
        onSave: @escaping (
            _ text: String, _ horizontalAlignment: AlbumTextHorizontalAlignment, _ verticalAlignment: AlbumTextVerticalAlignment,
            _ fontFamily: AlbumTextFontFamily, _ fontSize: Double, _ fontStyle: AlbumTextFontStyle
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
        _fontStyle = State(initialValue: target.currentFontStyle)
    }

    var body: some View {
        NavigationStack {
            Form {
                // § user request — "Cần có phần Preview ở phía trên cùng editor, trên phần input
                // text" — the very first section, above Content.
                Section("album.textBlock.edit.preview_section") {
                    previewBox
                }

                Section("album.textBlock.edit.content_section") {
                    textEditorField
                }

                Section("album.textBlock.edit.alignment_section") {
                    alignmentControls
                }

                Section("album.textBlock.edit.style_section") {
                    fontFamilyStrip
                    styleControl
                    fontSizeField
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
                        onSave(text, horizontalAlignment, verticalAlignment, fontFamily, sanitizedFontSize, fontStyle)
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { isTextEditorFocused = true }
        }
    }

    // MARK: - Preview

    /// § user request — "Phần preview không cần thể hiện hết text, nhưng cần thể hiện rõ độ lớn,
    /// font chữ": a fixed-height box (never grows with the actual text, so it can never itself
    /// need scrolling) showing up to 3 lines of the real current text — enough to read the actual
    /// font/style/size/alignment clearly without needing to reproduce the exact on-Page layout.
    /// Reuses `albumTextFont` (the same function `AlbumTextBlockView` renders the real Page with)
    /// so this can never silently drift from what Done will actually produce.
    private var previewBox: some View {
        Text(text.isEmpty ? localizedString("album.textBlock.placeholder", defaultValue: "Write here") : text)
            .font(albumTextFont(family: fontFamily, size: safeFontSize, style: fontStyle))
            .multilineTextAlignment(textAlignment)
            .opacity(text.isEmpty ? 0.35 : 1)
            .lineLimit(3)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: containerAlignment)
            .listRowInsets(EdgeInsets())
            .padding(12)
    }

    private var textAlignment: TextAlignment {
        switch horizontalAlignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private var containerAlignment: Alignment {
        switch (horizontalAlignment, verticalAlignment) {
        case (.left, .top): return .topLeading
        case (.center, .top): return .top
        case (.right, .top): return .topTrailing
        case (.left, .center): return .leading
        case (.center, .center): return .center
        case (.right, .center): return .trailing
        case (.left, .bottom): return .bottomLeading
        case (.center, .bottom): return .bottom
        case (.right, .bottom): return .bottomTrailing
        }
    }

    // MARK: - Content

    // § user report — "hiện giờ toàn 1 màu trắng, không có con trỏ, không có placeholder nên
    // không biết viết gì ở đâu" (fixed with a bordered box + placeholder + autofocus), followed by
    // — "Phần input để trong 1 khung không có viền ... chỉ cần trong phần card trắng là được": the
    // extra bordered/gray box turned out to be one frame too many now that this sits inside a
    // `Form` Section (itself already a white card) — removed, keeping only the placeholder overlay
    // (`.scrollContentBackground(.hidden)` is still what lets it show through `TextEditor`'s own
    // otherwise-opaque background) and the autofocus.
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
    }

    // MARK: - Alignment

    /// § user request — "Các phần căn lề, độ đậm sử dụng icon": icon-only segmented controls
    /// instead of text pickers — alignment glyphs are self-explanatory without a label.
    private var alignmentControls: some View {
        VStack(spacing: 12) {
            Picker("album.textBlock.edit.horizontal_alignment", selection: $horizontalAlignment) {
                Image(systemName: "text.alignleft").tag(AlbumTextHorizontalAlignment.left)
                Image(systemName: "text.aligncenter").tag(AlbumTextHorizontalAlignment.center)
                Image(systemName: "text.alignright").tag(AlbumTextHorizontalAlignment.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("album.textBlock.edit.vertical_alignment", selection: $verticalAlignment) {
                Image(systemName: "align.vertical.top").tag(AlbumTextVerticalAlignment.top)
                Image(systemName: "align.vertical.center").tag(AlbumTextVerticalAlignment.center)
                Image(systemName: "align.vertical.bottom").tag(AlbumTextVerticalAlignment.bottom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Style

    /// § user request — "Danh sách font chữ làm 1 dải ngang vuốt để chọn": a horizontal swipeable
    /// strip of chips (mirroring `AlbumPageViewer`'s own `layoutPickerHeader` pattern — same
    /// `ScrollViewReader` + auto-center-on-appear shape), each showing its own family name rendered
    /// *in* that family, so picking a font previews it directly in the chip itself.
    private var fontFamilyStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("album.textBlock.edit.font_family")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(AlbumTextFontFamily.allCases, id: \.self) { family in
                            fontFamilyChip(family).id(family)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    scrollProxy.scrollTo(fontFamily, anchor: .center)
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .padding(.horizontal, 4)
    }

    private func fontFamilyChip(_ family: AlbumTextFontFamily) -> some View {
        let isSelected = family == fontFamily
        return Button {
            fontFamily = family
        } label: {
            Text(family.rawValue)
                .font(albumTextFont(family: family, size: 15, style: .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    /// § user request — "font-weight sẽ thay bằng các định dạng cơ bản: Regular, Italic, Bold,
    /// Italic-Bold (sử dụng icon)": an icon-only segmented control over the 4 basic style
    /// permutations, replacing the previous thickness-scale weight picker entirely.
    private var styleControl: some View {
        Picker("album.textBlock.edit.font_style", selection: $fontStyle) {
            Image(systemName: "textformat").tag(AlbumTextFontStyle.regular)
            Image(systemName: "italic").tag(AlbumTextFontStyle.italic)
            Image(systemName: "bold").tag(AlbumTextFontStyle.bold)
            Image(systemName: "bold.italic").tag(AlbumTextFontStyle.boldItalic)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // § user request — "Ô cỡ chữ cho phép gõ số": lets the user type an exact size directly,
    // instead of only nudging it up/down one step at a time via the Stepper's own +/- buttons
    // (kept alongside, for quick small adjustments).
    //
    // § user report — "Tôi gõ luôn bị số 8 ở đầu": this used to re-clamp `fontSize` into
    // `8...200` on *every* keystroke (`.onChange(of: fontSize)`). While the field is momentarily
    // empty/incomplete mid-typing (e.g. backspacing "24" down to nothing before typing a new
    // number), `TextField(value:format:)` briefly binds `fontSize` to something below 8 (or an
    // invalid value entirely) — which that live clamp immediately snapped back to exactly `8` and
    // wrote back into the field, so the *next* digit typed landed after that stray "8" instead of
    // replacing it. Free typing is never touched now — the valid range is only enforced once, at
    // Done (`sanitizedFontSize`), never mid-edit.
    private var fontSizeField: some View {
        Stepper(value: $fontSize, in: 8...200, step: 2) {
            HStack {
                Text("album.textBlock.edit.font_size")
                Spacer()
                TextField("", value: $fontSize, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)
            }
        }
    }

    /// § user report — the CoreGraphics "invalid numeric value (NaN...)" console warning: the same
    /// momentarily-empty/invalid `TextField` state above was being fed straight into
    /// `albumTextFont`/CoreText for the live preview. Never renders with a non-finite or
    /// non-positive size, regardless of what `fontSize` transiently holds mid-edit.
    private var safeFontSize: CGFloat {
        fontSize.isFinite && fontSize > 0 ? fontSize : 32
    }

    /// The one point the valid `8...200` range is actually enforced — once, at Done — rather than
    /// continuously while the user is still typing (see `fontSizeField`'s own doc comment).
    private var sanitizedFontSize: Double {
        let base = fontSize.isFinite ? fontSize : 32
        return min(max(base, 8), 200)
    }
}
