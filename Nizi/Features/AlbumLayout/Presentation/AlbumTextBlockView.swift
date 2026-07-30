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
    let frame: CGRect
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
    let fontWeight: AlbumTextFontWeight
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
            .multilineTextAlignment(textAlignment)
            // § "Nếu là placeholder thì chữ sẽ bị mờ. Nếu là nội dung user nhập vào thì chữ mới rõ
            // nét" — dimmed for the placeholder, full opacity for real content.
            .opacity(isPlaceholder ? 0.35 : 1)
            .frame(width: frame.width, height: frame.height, alignment: containerAlignment)
            // § "Chữ sẽ hiển thị trong khối đó, không tràn ra ngoài" — hard clip regardless of how
            // much text there is, on top of whatever wrapping `.frame`'s proposed width already
            // encourages.
            .clipped()
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
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
        albumTextFont(family: fontFamily, size: scaledFontSize, weight: fontWeight)
    }
}

/// Shared by `AlbumTextBlockView` (the real Page render) and `AlbumTextBlockEditSheet` (its own
/// live style preview, plus the font-strip's per-chip sample) — one place that turns a
/// family/size/weight combination into an actual `Font`, so the edit screen's preview can never
/// silently drift from what the Page itself will really show.
func albumTextFont(family: AlbumTextFontFamily, size: CGFloat, weight: AlbumTextFontWeight) -> Font {
    guard family != .system else {
        return .system(size: size, weight: weight.swiftUIWeight)
    }
    return .custom(albumTextBestMatchingFontName(family: family.rawValue, weight: weight), size: size)
}

/// `Font.custom` needs an exact PostScript font name, not a family display name (e.g.
/// `"HelveticaNeue-Bold"`, not `"Helvetica Neue"`) — and which PostScript names exist, and which
/// one corresponds to which weight, differs per family and isn't something worth hardcoding (and
/// risking a typo silently falling back to the system font for one family). `UIFont.fontNames
/// (forFamilyName:)` asks iOS itself, which is the only reliable source.
func albumTextBestMatchingFontName(family: String, weight: AlbumTextFontWeight) -> String {
    let candidates = UIFont.fontNames(forFamilyName: family)
    guard !candidates.isEmpty else { return family }
    if let match = candidates.first(where: { $0.localizedCaseInsensitiveContains(weight.postScriptNameHint) }) {
        return match
    }
    // This family doesn't ship a face for the requested weight (many of the curated families
    // only have one) — fall back to whatever looks like its regular/default face.
    return candidates.first(where: { $0.localizedCaseInsensitiveContains("regular") }) ?? candidates[0]
}

extension AlbumTextFontWeight {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    /// Substring most iOS PostScript font names use to signal this weight (e.g.
    /// `"HelveticaNeue-Bold"`, `"AvenirNext-Medium"`).
    var postScriptNameHint: String {
        switch self {
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "SemiBold"
        case .bold: return "Bold"
        }
    }
}
