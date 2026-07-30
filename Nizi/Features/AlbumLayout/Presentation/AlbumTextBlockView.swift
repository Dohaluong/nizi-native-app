//
//  AlbumTextBlockView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// Renders one text block's *resolved* style (already picked by the caller — either an
/// `AlbumTextAssignment`'s own style, if this Page has one, or the layout's `AlbumTextBlock`
/// default otherwise; see `AlbumPageRenderer.textBlockView`) — either the real per-Page content
/// typed into it (`content`, crisp/full-opacity) or, while that's still empty, the localized
/// placeholder (§ "Placeholder đều có dạng: Viết ở đây hoặc Write here", dimmed — § "Nếu là
/// placeholder thì chữ sẽ bị mờ. Nếu là nội dung user nhập vào thì chữ mới rõ nét").
/// `AlbumPageRenderer` sizes/positions this exactly like a photo slot; this view only needs its
/// own pixel `frame` and already-resolved style — it doesn't know or care whether that style came
/// from an assignment or a block default.
struct AlbumTextBlockView: View {
    /// § bug report — "khi ấn vào ảnh cũng ra editor text": this used to take the whole `CGRect`
    /// and call `.position(x:y:)` as its own *last* modifier internally. `AlbumPageRenderer` then
    /// attached its `.contentShape(Rectangle()).onTapGesture` *outside*, wrapping this already-
    /// positioned view — but `.position()` reports a flexible ("fill whatever space my parent
    /// gives me") size to its own parent, and a gesture/content-shape attached *after* `.position()`
    /// sizes itself to that reported flexible size, not the view's actual visible bounds. In
    /// practice that meant the text block's tap target silently expanded to cover the entire
    /// canvas (this view sits inside the same `ZStack` as every photo slot, so nothing else with a
    /// gesture on top ever blocked it) — any tap anywhere, including squarely on a photo, hit the
    /// text block's `onTapGesture` first. Fixed by taking only `size` here (never doing its own
    /// `.position()` at all) — `AlbumPageRenderer.textBlockView` now attaches the gesture to this
    /// properly-*bounded* view first and applies `.position()` itself afterward, exactly mirroring
    /// how `slotView` already correctly handles photo slots.
    let size: CGSize
    let horizontalAlignment: AlbumTextHorizontalAlignment
    let verticalAlignment: AlbumTextVerticalAlignment
    let fontFamily: AlbumTextFontFamily
    /// § user report — "Tỷ lệ chữ to so với cả trang": the source font size is in the layout's own
    /// `referenceCanvas` units, exactly like `frame`/`AlbumLayoutSlot.cornerRadius` — it must be
    /// scaled the same way those already are (by the canvas→screen scale factor) before use as an
    /// actual on-screen point size, matching how the Studio's own canvas preview already scales it
    /// (`fontSizePx = (textBlock.fontSize / canvas.width) * stagePixelSize.width`). Rendering the
    /// raw font size unscaled (the previous bug) made text huge on any canvas bigger than the
    /// device's own point size — which every real `referenceCanvas` is (e.g. `1000×1000` against a
    /// page that's only a few hundred points on screen). The caller (`AlbumPageRenderer`) does the
    /// scaling since it's the one with `scaleX`/`scaleY` in scope.
    let scaledFontSize: CGFloat
    let fontStyle: AlbumTextFontStyle
    /// The real, user-typed content for this Page's copy of this text block — `nil`/empty means
    /// "nothing typed yet," which shows the placeholder instead.
    let content: String?

    private var isPlaceholder: Bool { content?.isEmpty ?? true }

    private var displayText: String {
        if let content, !content.isEmpty { return content }
        return localizedString("album.textBlock.placeholder", defaultValue: "Write here")
    }

    var body: some View {
        Text(displayText)
            .font(font)
            // § "Regular, Italic, Bold, Underline" — underline is a text *decoration*, not a font
            // face choice at all, so it's a separate modifier rather than something `font` itself
            // could ever express (`Font` has no underline concept).
            .underline(fontStyle == .underline)
            .multilineTextAlignment(textAlignment)
            // § "Nếu là placeholder thì chữ sẽ bị mờ. Nếu là nội dung user nhập vào thì chữ mới rõ
            // nét" — dimmed for the placeholder, full opacity for real content.
            .opacity(isPlaceholder ? 0.35 : 1)
            .frame(width: size.width, height: size.height, alignment: containerAlignment)
            // § "Chữ sẽ hiển thị trong khối đó, không tràn ra ngoài" — hard clip regardless of how
            // much text there is, on top of whatever wrapping `.frame`'s proposed width already
            // encourages. Deliberately *no* `.position()` here — see this type's own doc comment.
            .clipped()
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

    private var font: Font {
        albumTextFont(family: fontFamily, size: scaledFontSize, style: fontStyle)
    }
}

/// Shared by `AlbumTextBlockView` (the real Page render) and `AlbumTextBlockEditSheet` (its own
/// live style preview, plus the font-strip's per-chip sample) — one place that turns a
/// family/size/style combination into an actual `Font`, so the edit screen's preview can never
/// silently drift from what the Page itself will really show.
///
/// The system family is the one case handled without any named-face lookup at all — SwiftUI's own
/// `.bold()`/`.italic()` modifiers already compose correctly on top of `Font.system`, and there's
/// no meaningful "PostScript face" concept for it the way there is for a real installed family.
func albumTextFont(family: AlbumTextFontFamily, size: CGFloat, style: AlbumTextFontStyle) -> Font {
    guard family != .system else {
        var font = Font.system(size: size)
        if style == .bold { font = font.bold() }
        if style == .italic { font = font.italic() }
        return font
    }
    return .custom(albumTextBestMatchingFontName(family: family.rawValue, style: style), size: size)
}

/// `Font.custom` needs an exact PostScript font name, not a family display name (e.g.
/// `"HelveticaNeue-Bold"`, not `"Helvetica Neue"`) — and which PostScript names exist, and which
/// one corresponds to which style, differs per family and isn't something worth hardcoding (and
/// risking a typo silently falling back to the system font for one family). `UIFont.fontNames
/// (forFamilyName:)` asks iOS itself, which is the only reliable source. Deliberately doesn't just
/// apply SwiftUI's own `.bold()`/`.italic()` on top of a resolved custom face — those synthesize a
/// faux slant/weight algorithmically, which looks worse than an actual hand-designed italic/bold
/// face the family already ships (exactly what this look-up finds instead, when one exists).
/// `.underline` needs no face lookup at all — it's just the regular face plus a separate
/// `.underline(_:)` modifier (see `AlbumTextBlockView.body`), same as `.regular` here.
func albumTextBestMatchingFontName(family: String, style: AlbumTextFontStyle) -> String {
    let candidates = UIFont.fontNames(forFamilyName: family)
    guard !candidates.isEmpty else { return family }

    func has(_ name: String, _ token: String) -> Bool {
        name.localizedCaseInsensitiveContains(token)
    }
    func isItalic(_ name: String) -> Bool { has(name, "Italic") || has(name, "Oblique") }
    func isBold(_ name: String) -> Bool { has(name, "Bold") }

    let match: String?
    switch style {
    case .regular, .underline:
        match = nil
    case .bold:
        match = candidates.first { isBold($0) && !isItalic($0) }
    case .italic:
        match = candidates.first { isItalic($0) && !isBold($0) }
    }
    // No exact match — either `.regular`/`.underline` (neither needs one), or this family doesn't
    // ship a face for the requested style (many of the curated families only have one) — fall
    // back to whatever looks like its regular/default face.
    return match ?? candidates.first(where: { has($0, "Regular") }) ?? candidates[0]
}
