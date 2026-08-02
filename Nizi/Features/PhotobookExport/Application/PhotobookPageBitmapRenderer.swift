//
//  PhotobookPageBitmapRenderer.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/2/26.
//

import CoreGraphics
import SwiftUI
import UIKit

/// Renders one Page's background, photo slots (crop/scale/offset via the same
/// `AlbumPhotoCropGeometry` `AlbumPhotoView` uses), gradient overlays, corner-radius clipping, and
/// text blocks (same font resolution `AlbumTextBlockView` uses) into a plain bitmap — never a PDF
/// context. `PhotobookPDFExporter` JPEG-encodes the result and writes it as one PDF page in a
/// later, fully synchronous step (see that type's own doc comment for why the PDF write itself
/// must never straddle an `await`). Deliberately *not* a SwiftUI `View`: no `@State`, no gestures,
/// no animation, no async photo loading of its own (`images` must already be resolved) — a plain,
/// synchronous, easily-testable drawing routine, and the one place besides `AlbumPageRenderer` that
/// turns an `AlbumPageLayout` + a Page's assignments into pixels, reusing the exact same Domain
/// model and crop/font rules (only the backend differs: Core Graphics imperative calls instead of
/// SwiftUI declarative views).
struct PhotobookPageBitmapRenderer {
    /// 3000×3000px — real pixels, never scaled by `UIScreen.main.scale` (`format.scale = 1` below
    /// forces that regardless of the device this runs on).
    static let outputSize = CGSize(width: 3000, height: 3000)

    /// `images` is keyed by `AlbumLayoutSlot.id`, already resolved to a high-quality `CGImage` at
    /// (at least) that slot's real pixel footprint — this function does no PhotoKit work and no
    /// `await`s. Throws only if the underlying bitmap context/image itself can't be created (an
    /// environment/memory failure, not a content one — a missing photo is the caller's problem to
    /// resolve or fail on *before* calling this).
    func render(page: AlbumViewerPage, layout: AlbumPageLayout, images: [String: CGImage]) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        // § "Không tạo bitmap scale theo UIScreen.main.scale" — `.preferred()` alone still adapts
        // to the current device; these three overrides are what actually pin the output to real,
        // device-independent 3000×3000 pixels, sRGB, and an opaque (alpha-free, JPEG-safe) buffer.
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard // sRGB, not a wide-gamut (P3) buffer on capable devices.

        let renderer = UIGraphicsImageRenderer(size: Self.outputSize, format: format)
        // `UIGraphicsImageRenderer` pushes/pops its own `CGContext` as the "current" one only for
        // the duration of this synchronous closure — every `UIBezierPath`/`UIImage`/
        // `NSAttributedString` convenience call below is safe precisely because nothing here ever
        // suspends (`render` itself is not `async`); see `PhotobookPDFExporter` for why that
        // property matters far beyond just this function.
        let uiImage = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            draw(page: page, layout: layout, images: images, into: context)
        }
        guard let cgImage = uiImage.cgImage else { throw PhotobookExportError.writeFailed }
        return cgImage
    }

    private func draw(page: AlbumViewerPage, layout: AlbumPageLayout, images: [String: CGImage], into context: CGContext) {
        let scaleX = Self.outputSize.width / layout.referenceCanvas.width
        let scaleY = Self.outputSize.height / layout.referenceCanvas.height
        let uniformScale = min(scaleX, scaleY)

        // § "Nền phải được fill hoàn chỉnh trước khi vẽ vì JPEG không hỗ trợ transparency" — this
        // is the very first thing drawn, covering the whole canvas, before any slot/text.
        drawBackground(layout.background, canvasRect: CGRect(origin: .zero, size: Self.outputSize), context: context)

        let assignmentsBySlotId = Dictionary(uniqueKeysWithValues: page.page.assignments.map { ($0.slotId, $0) })
        for slot in layout.slots.sorted(by: { $0.order < $1.order }) {
            let rect = CGRect(
                x: slot.frame.x * scaleX, y: slot.frame.y * scaleY,
                width: slot.frame.width * scaleX, height: slot.frame.height * scaleY
            )
            drawSlot(
                slot, assignment: assignmentsBySlotId[slot.id], image: assignmentsBySlotId[slot.id].flatMap { images[$0.slotId] },
                rect: rect, cornerRadius: slot.cornerRadius * uniformScale, context: context
            )
        }

        let textAssignmentsByBlockId = Dictionary(uniqueKeysWithValues: page.page.textAssignments.map { ($0.textBlockId, $0) })
        for block in layout.textBlocks {
            let rect = CGRect(
                x: block.frame.x * scaleX, y: block.frame.y * scaleY,
                width: block.frame.width * scaleX, height: block.frame.height * scaleY
            )
            drawText(block, assignment: textAssignmentsByBlockId[block.id], rect: rect, uniformScale: uniformScale, context: context)
        }
    }

    // MARK: - Background

    private func drawBackground(_ background: AlbumLayoutBackground, canvasRect: CGRect, context: CGContext) {
        switch background.type {
        case .solid:
            let color = UIColor(Color(albumHex: background.value) ?? .white)
            context.saveGState()
            color.setFill()
            context.fill(canvasRect)
            context.restoreGState()
        }
    }

    // MARK: - Photo slot

    private func drawSlot(
        _ slot: AlbumLayoutSlot, assignment: AlbumPhotoAssignment?, image: CGImage?,
        rect: CGRect, cornerRadius: CGFloat, context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()

        if let image, let assignment {
            let imageSize = CGSize(width: image.width, height: image.height)
            let placement = AlbumPhotoCropGeometry.renderRect(
                imageSize: imageSize, frameSize: rect.size, fill: slot.contentMode == .fill, crop: assignment.crop
            ).offsetBy(dx: rect.minX, dy: rect.minY)
            // `UIImage.draw(in:)`, not raw `CGContext.draw(_:in:)` — the latter draws a `CGImage`
            // assuming Core Graphics' native bottom-left/Y-up space regardless of the context's
            // own CTM, which renders upside down inside `UIGraphicsImageRenderer`'s top-left/Y-down
            // context (the same reason every other UIKit convenience call here — `UIBezierPath`,
            // `NSAttributedString` — already "just works": they all know to honor the current
            // context's flip, `CGContext.draw` alone does not). `UIImage(cgImage:)` costs nothing
            // extra (no re-decode, just a wrapper) and is the same call `PhotobookPageBitmapRenderer`'s
            // PDF-context predecessor used successfully — proven correct orientation, not guessed.
            UIImage(cgImage: image).draw(in: placement)
        } else {
            UIColor.secondarySystemFill.setFill()
            context.fill(rect)
        }

        if let overlay = slot.gradientOverlay {
            drawGradientOverlay(overlay, rect: rect, context: context)
        }
    }

    private func drawGradientOverlay(_ overlay: AlbumSlotGradientOverlay, rect: CGRect, context: CGContext) {
        let extent = CGFloat(min(max(overlay.extentPercent / 100, 0), 1))
        let dark = UIColor.black.withAlphaComponent(CGFloat(min(max(overlay.opacity, 0), 1))).cgColor
        let clear = UIColor.black.withAlphaComponent(0).cgColor

        let colors: [CGColor]
        let locations: [CGFloat]
        switch overlay.edge {
        case .top, .left:
            colors = [dark, clear, clear]
            locations = [0, extent, 1]
        case .bottom, .right:
            colors = [clear, clear, dark]
            locations = [0, 1 - extent, 1]
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }

        let start: CGPoint
        let end: CGPoint
        switch overlay.edge {
        case .top, .bottom:
            start = CGPoint(x: rect.midX, y: rect.minY)
            end = CGPoint(x: rect.midX, y: rect.maxY)
        case .left, .right:
            start = CGPoint(x: rect.minX, y: rect.midY)
            end = CGPoint(x: rect.maxX, y: rect.midY)
        }

        context.saveGState()
        UIBezierPath(rect: rect).addClip()
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }

    // MARK: - Text block

    private func drawText(
        _ block: AlbumTextBlock, assignment: AlbumTextAssignment?, rect: CGRect, uniformScale: CGFloat, context: CGContext
    ) {
        let horizontalAlignment = assignment?.horizontalAlignment ?? block.horizontalAlignment
        let verticalAlignment = assignment?.verticalAlignment ?? block.verticalAlignment
        let fontFamily = assignment?.fontFamily ?? block.fontFamily
        let fontStyle = assignment?.fontStyle ?? block.fontStyle
        let textColorHex = assignment?.textColor ?? block.textColor
        // § user request — "không hiện chữ placeholder trong bản xuất PDF": unlike
        // `AlbumTextBlockView` (which shows `block.kind.placeholderText`, dimmed, as an *editing*
        // affordance so an empty block isn't invisible on screen), export has no such need — a
        // block with no real, user-typed content simply draws nothing at all.
        guard let content = assignment?.text, !content.isEmpty else { return }

        // § "Text phải được vẽ trực tiếp ở kích thước đích 3000 px" — `uniformScale` already maps
        // the layout's `referenceCanvas` units straight to the 3000×3000 output, same as every
        // slot/frame above; there is no intermediate point-space step to drift from.
        let scaledFontSize = (assignment?.fontSize ?? block.fontSize) * uniformScale
        let font = resolvedUIFont(family: fontFamily, size: scaledFontSize, style: fontStyle)
        let color = UIColor(Color(albumHex: textColorHex) ?? .primary)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = nsTextAlignment(horizontalAlignment)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle
        ]
        if fontStyle == .underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        let attributed = NSAttributedString(string: content, attributes: attributes)
        let drawOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let measuredHeight = attributed.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: drawOptions, context: nil).height
        let clampedHeight = min(measuredHeight, rect.height)

        let originY: CGFloat
        switch verticalAlignment {
        case .top: originY = rect.minY
        case .center: originY = rect.minY + (rect.height - clampedHeight) / 2
        case .bottom: originY = rect.maxY - clampedHeight
        }
        let drawRect = CGRect(x: rect.minX, y: originY, width: rect.width, height: clampedHeight)

        context.saveGState()
        UIBezierPath(rect: rect).addClip()
        // `NSAttributedString.draw(with:options:context:)` is a UIKit convenience that paints
        // into whatever the *current* graphics context is — safe here only because
        // `UIGraphicsImageRenderer` already made `context` the current one for this entire
        // synchronous closure (see `render(page:layout:images:)`'s own doc comment).
        attributed.draw(with: drawRect, options: drawOptions, context: nil)
        context.restoreGState()
    }

    private func nsTextAlignment(_ alignment: AlbumTextHorizontalAlignment) -> NSTextAlignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    /// Mirrors `albumTextFont`/`albumTextBestMatchingFontName` (`AlbumTextBlockView.swift`) but
    /// resolves a `UIFont` instead of a SwiftUI `Font` — `NSAttributedString`/Core Text need the
    /// concrete type. Uses the exact same `UIFont.fontNames(forFamilyName:)` best-match lookup, so
    /// export never picks a different face than what the live editor already shows.
    private func resolvedUIFont(family: AlbumTextFontFamily, size: CGFloat, style: AlbumTextFontStyle) -> UIFont {
        guard family != .system else {
            var descriptor = UIFont.systemFont(ofSize: size).fontDescriptor
            var traits: UIFontDescriptor.SymbolicTraits = []
            if style == .bold { traits.insert(.traitBold) }
            if style == .italic { traits.insert(.traitItalic) }
            if !traits.isEmpty, let withTraits = descriptor.withSymbolicTraits(traits) {
                descriptor = withTraits
            }
            return UIFont(descriptor: descriptor, size: size)
        }
        let name = albumTextBestMatchingFontName(family: family.rawValue, style: style)
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
    }
}
