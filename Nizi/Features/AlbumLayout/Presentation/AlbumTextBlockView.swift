//
//  AlbumTextBlockView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// Renders one `AlbumTextBlock` — always its localized placeholder text (§ "Placeholder đều có
/// dạng: Viết ở đây hoặc Write here"), since there is no per-Album, user-authored text content yet
/// (see `AlbumTextBlock`'s own doc comment). `AlbumPageRenderer` sizes/positions this exactly like
/// a photo slot; this view only needs to know its own pixel `frame` and style.
struct AlbumTextBlockView: View {
    let textBlock: AlbumTextBlock
    let frame: CGRect

    var body: some View {
        Text(localizedString("album.textBlock.placeholder", defaultValue: "Write here"))
            .font(font)
            .multilineTextAlignment(textAlignment)
            .frame(width: frame.width, height: frame.height, alignment: containerAlignment)
            // § "Chữ sẽ hiển thị trong khối đó, không tràn ra ngoài" — hard clip regardless of how
            // much text there is, on top of whatever wrapping `.frame`'s proposed width already
            // encourages.
            .clipped()
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    private var textAlignment: TextAlignment {
        switch textBlock.horizontalAlignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private var containerAlignment: Alignment {
        switch (textBlock.horizontalAlignment, textBlock.verticalAlignment) {
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
        guard textBlock.fontFamily != .system else {
            return .system(size: textBlock.fontSize, weight: textBlock.fontWeight.swiftUIWeight)
        }
        return .custom(Self.bestMatchingFontName(family: textBlock.fontFamily.rawValue, weight: textBlock.fontWeight), size: textBlock.fontSize)
    }

    /// `Font.custom` needs an exact PostScript font name, not a family display name (e.g.
    /// `"HelveticaNeue-Bold"`, not `"Helvetica Neue"`) — and which PostScript names exist, and
    /// which one corresponds to which weight, differs per family and isn't something worth
    /// hardcoding (and risking a typo silently falling back to the system font for one family).
    /// `UIFont.fontNames(forFamilyName:)` asks iOS itself, which is the only reliable source.
    private static func bestMatchingFontName(family: String, weight: AlbumTextFontWeight) -> String {
        let candidates = UIFont.fontNames(forFamilyName: family)
        guard !candidates.isEmpty else { return family }
        if let match = candidates.first(where: { $0.localizedCaseInsensitiveContains(weight.postScriptNameHint) }) {
            return match
        }
        // This family doesn't ship a face for the requested weight (many of the curated families
        // only have one) — fall back to whatever looks like its regular/default face.
        return candidates.first(where: { $0.localizedCaseInsensitiveContains("regular") }) ?? candidates[0]
    }
}

private extension AlbumTextFontWeight {
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
