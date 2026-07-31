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
    let currentTextColor: String
    /// Template-level only (never per-Page — see `AlbumTextBlockKind`'s own doc comment); used
    /// here just to show the same kind-specific placeholder the real Page does while `currentText`
    /// is still empty.
    let currentKind: AlbumTextBlockKind
    /// § user request — "trang bìa sẽ có cấu trúc như trang ruột ... chạm vào để sửa chữ tương tự
    /// như trang khác": the cover's text blocks aren't real `AlbumTextAssignment`s living on a
    /// Page in `draft.spreads` (see `AlbumPageViewer.coverAsViewerPage`), so Save dispatches to
    /// `AlbumEditAction.updateCoverTextBlock` instead of `.updateTextBlock` — this flag is what
    /// `AlbumPageViewer`'s own `.sheet(item: $textBlockEditTarget)` branches on.
    var isCoverText: Bool = false
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
        _ fontFamily: AlbumTextFontFamily, _ fontSize: Double, _ fontStyle: AlbumTextFontStyle, _ textColor: String
    ) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var horizontalAlignment: AlbumTextHorizontalAlignment
    @State private var verticalAlignment: AlbumTextVerticalAlignment
    @State private var fontFamily: AlbumTextFontFamily
    @State private var fontSize: Double
    @State private var fontStyle: AlbumTextFontStyle
    @State private var textColor: String
    /// Not user-editable here (see `AlbumTextBlockEditTarget.currentKind`'s own doc comment) — a
    /// plain `let`, not `@State`.
    private let kind: AlbumTextBlockKind
    // § user report — "không có con trỏ ... không biết viết gì ở đâu": auto-focusing the moment
    // this sheet appears means the keyboard is already up and the cursor already blinking, so
    // there's no ambiguity about where to type.
    @FocusState private var isTextEditorFocused: Bool

    init(
        target: AlbumTextBlockEditTarget,
        onSave: @escaping (
            _ text: String, _ horizontalAlignment: AlbumTextHorizontalAlignment, _ verticalAlignment: AlbumTextVerticalAlignment,
            _ fontFamily: AlbumTextFontFamily, _ fontSize: Double, _ fontStyle: AlbumTextFontStyle, _ textColor: String
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
        _textColor = State(initialValue: target.currentTextColor)
        kind = target.currentKind
    }

    var body: some View {
        NavigationStack {
            // § user request — "Giao diện tôi cần gọn hơn 1 chút ... Không cần các tiêu đề. Người
            // dùng nhìn biểu tượng là hiểu": every `Section` below dropped its title text — still
            // visually grouped by the Form's own row dividers, just without a caption explaining
            // what's obvious from the icons themselves (Preview/Content are the two exceptions
            // that stay recognizable purely from their own content/position, same reasoning).
            Form {
                // § user report — "Phần chữ Preview không để trong nền trắng mà để nền xám như
                // phần xung quanh": painting this row's own background the same gray as the
                // Form's grouped background (instead of the default white row background) makes
                // it blend into the surrounding page rather than reading as its own card.
                Section {
                    previewBox
                }
                .listRowBackground(Color(.systemGroupedBackground))

                Section {
                    textEditorField
                }

                // § user report — "3 khối icon căn lề, font chữ và kiểu chữ cần đặt trong 1 card
                // màu trắng, khoảng cách các khối cách nhau không quá xa": alignment, font family,
                // and style+size used to be 3 separate `Section`s (3 separate white cards with a
                // visible gap between each), which read as much farther apart than intended — one
                // shared `Section` puts all three in a single card with only ordinary row spacing
                // between them.
                Section {
                    alignmentControls
                    fontFamilyStrip
                    styleAndSizeRow
                    // § user request — "còn cần chọn màu chữ": shares the same merged card as
                    // alignment/font/style rather than its own `Section`, for the same "khoảng
                    // cách các khối cách nhau không quá xa" reasoning.
                    colorControl
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
                        onSave(text, horizontalAlignment, verticalAlignment, fontFamily, sanitizedFontSize, fontStyle, textColor)
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
        Text(text.isEmpty ? kind.placeholderText : text)
            .font(albumTextFont(family: fontFamily, size: safeFontSize, style: fontStyle))
            .foregroundStyle(Color(albumHex: textColor) ?? .primary)
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

    /// § user request — "6 icon căn lề cho vào 1 hàng": horizontal (3) and vertical (3) alignment
    /// are still two independent `Picker`s (two different axes, two different bindings) but now
    /// sit side by side in one `HStack` instead of stacked — reads as one row of 6 icons.
    private var alignmentControls: some View {
        HStack(spacing: 8) {
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
        // § "Không cần các tiêu đề" — no visible caption above the strip anymore, but VoiceOver
        // still needs to know what this row of chips actually is (unlike the alignment/style
        // icons, plain family-name chips have no icon of their own to intuit from).
        .accessibilityLabel(Text("album.textBlock.edit.font_family"))
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

    /// § user request — "1 hàng cho kiểu chữ và cỡ chữ": style and size share one row. Style
    /// expands to fill the remaining width (§ "icon button cần đủ to để bấm" — bigger segments,
    /// bigger tap targets), size stays compact on the trailing edge.
    private var styleAndSizeRow: some View {
        HStack(spacing: 12) {
            styleControl
                .frame(maxWidth: .infinity)
            // § user report — "cỡ chữ giờ hơi bé so với trang ... 1 trang ảnh vuông khi in ra thực
            // tế sẽ tương đương 20x20cm, nên tôi cần cỡ chữ thể hiện tương ứng": `fontSize` is
            // stored/rendered in the layout's own `referenceCanvas` units (same space as `frame`),
            // which don't mean anything on their own — the field now shows/accepts real print
            // points instead (`fontSizeInPoints`), computed from the one physical anchor this
            // whole app already assumes (a square page's `1000`-unit canvas == 20×20cm), so typing
            // "24" here means an actual 24pt caption on the printed page, the same way it would in
            // any word processor — not a mystery number in some other unit.
            Stepper(value: fontSizeInPoints, in: Self.minFontSizePoints...Self.maxFontSizePoints, step: 1) {
                // § "Ô cỡ chữ cho phép gõ số": typing an exact value directly, alongside the
                // Stepper's own +/- for quick nudges. Nothing here clamps live (see the "gõ luôn
                // bị số 8 ở đầu" bug this avoided by design) — the valid range is only enforced
                // once, at Done (`sanitizedFontSize`).
                TextField("", value: fontSizeInPoints, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .accessibilityLabel(Text("album.textBlock.edit.font_size"))
            }
            .fixedSize()
        }
    }

    /// § user report — "1 trang ảnh vuông khi in ra thực tế sẽ tương đương 20x20cm": the one fixed
    /// physical anchor every reference canvas in this app already implies (`DEFAULT_REFERENCE_
    /// CANVAS.square == 1000×1000`, portrait/landscape scale the same canvas-units-per-cm ratio
    /// against their own longer edge) — `1000` canvas units along a page's shorter edge is always
    /// `20`cm physically, regardless of format, so this ratio is a fixed constant, not derived from
    /// whichever specific layout happens to be open.
    private static let canvasUnitsPerCm: Double = 1000 / 20
    /// 1cm == 28.3465pt (the standard print/typographic conversion) — combined with
    /// `canvasUnitsPerCm` above, this is what actually lets a typed point value mean a real,
    /// physical size on the printed page.
    private static let pointsPerCm: Double = 28.3465
    private static let canvasUnitsPerPoint: Double = canvasUnitsPerCm / pointsPerCm

    private static let minFontSizePoints: Double = 6
    private static let maxFontSizePoints: Double = 144

    /// The editor's own font-size field/Stepper operate on this (points) — `fontSize` itself stays
    /// in canvas units throughout (unchanged storage/rendering unit, same space `AlbumPageRenderer`
    /// already scales against), so this is purely a presentation-layer conversion, not a schema
    /// change.
    ///
    /// § user report — "Phần hiển thị cỡ chữ đang bị lẻ???: 26,07878 là sao?": `canvasUnitsPerPoint`
    /// is an irrational-ish ratio (`50 / 28.3465`), so dividing by it directly produced a long,
    /// meaningless decimal the instant `fontSize` wasn't an exact multiple of it (which is
    /// essentially always). Font sizes are conventionally whole points anyway — rounding here means
    /// the field only ever shows/holds a clean integer; `set` still converts back to the precise
    /// (non-integer) canvas-unit equivalent underneath, same as before.
    private var fontSizeInPoints: Binding<Double> {
        Binding(
            get: { (safeFontSize / Self.canvasUnitsPerPoint).rounded() },
            set: { fontSize = $0 * Self.canvasUnitsPerPoint }
        )
    }

    /// § user request — "tôi cần điều chỉnh về 4 kiểu Cơ bản hơn, dùng icon đúng: Regular, Italic,
    /// Bold, Underline. icon button cần đủ to để bấm": real SF Symbols (all 4 confirmed to render,
    /// unlike the earlier `"bold.italic"` combo icon that didn't) instead of the previous "A" glyph
    /// approach, at a bigger point size and with `.controlSize(.large)` so each segment is an
    /// actually comfortable tap target — not just visually distinct.
    private var styleControl: some View {
        Picker("album.textBlock.edit.font_style", selection: $fontStyle) {
            Image(systemName: "textformat").tag(AlbumTextFontStyle.regular)
            Image(systemName: "italic").tag(AlbumTextFontStyle.italic)
            Image(systemName: "bold").tag(AlbumTextFontStyle.bold)
            Image(systemName: "underline").tag(AlbumTextFontStyle.underline)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .imageScale(.large)
        .labelsHidden()
    }

    // MARK: - Color

    /// § user request — "còn cần chọn màu chữ": a plain system `ColorPicker`, bound through
    /// `colorBinding` so the model keeps storing the same `"#RRGGBB"` string shape every other
    /// color field (`AlbumLayoutBackground.value`) already uses — this view never stores a `Color`
    /// itself.
    private var colorControl: some View {
        ColorPicker(selection: colorBinding, supportsOpacity: false) {
            Text("album.textBlock.edit.text_color")
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(albumHex: textColor) ?? .primary },
            set: { textColor = $0.albumHexString }
        )
    }

    /// § user report — the CoreGraphics "invalid numeric value (NaN...)" console warning: the same
    /// momentarily-empty/invalid `TextField` state above was being fed straight into
    /// `albumTextFont`/CoreText for the live preview. Never renders with a non-finite or
    /// non-positive size, regardless of what `fontSize` transiently holds mid-edit.
    private var safeFontSize: CGFloat {
        fontSize.isFinite && fontSize > 0 ? fontSize : 32
    }

    /// The one point the valid range is actually enforced — once, at Done — rather than
    /// continuously while the user is still typing (see `styleAndSizeRow`'s own doc comment). Bounds
    /// are `minFontSizePoints`/`maxFontSizePoints` converted into this same canvas-unit space
    /// `fontSize` itself is always stored/rendered in.
    private var sanitizedFontSize: Double {
        let base = fontSize.isFinite ? fontSize : 32
        return min(max(base, Self.minFontSizePoints * Self.canvasUnitsPerPoint), Self.maxFontSizePoints * Self.canvasUnitsPerPoint)
    }
}
