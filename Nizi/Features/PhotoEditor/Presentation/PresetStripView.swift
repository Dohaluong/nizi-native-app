//
//  PresetStripView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI
import UIKit

/// The Preset tool tray (PHOTO-EDITOR.md § 7.2) — a horizontally scrolling row of preset
/// thumbnails rendered from the photo actually being edited, plus an intensity slider for
/// whichever preset is selected. `viewModel` is a reference type, so this reads/writes it
/// directly; no `@Bindable`/`$`-binding plumbing needed for a plain `Slider(value: Binding(get:
/// set:))`.
struct PresetStripView: View {
    let viewModel: PhotoEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.isInheritingCollectionStyle {
                inheritanceIndicator
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PhotoEditorToolTrayMetrics.cellSpacing) {
                    ForEach(viewModel.presets) { preset in
                        PresetThumbnailButton(
                            preset: preset,
                            isSelected: preset.id == viewModel.selectedPresetId
                        ) {
                            viewModel.selectPreset(preset)
                        }
                    }
                }
                .padding(.horizontal, PhotoEditorToolTrayMetrics.horizontalPadding)
            }

            // Always present (never conditionally omitted) so the tray's height stays constant
            // switching to/from `Original` (which has no intensity to show) — `.opacity(0)` hides
            // the content in place instead of collapsing the row and reflowing everything below it.
            intensityRow
                .opacity(viewModel.selectedPresetId == PresetDefinition.originalId ? 0 : 1)
                .allowsHitTesting(viewModel.selectedPresetId != PresetDefinition.originalId)
        }
        .padding(.vertical, 12)
    }

    /// § 12.3 — only ever shown while this photo's preset still matches its Album/Event's saved
    /// style; the moment the two diverge this photo is just editing its own preset like any other,
    /// so there's no "custom for this photo" state left to call out separately.
    private var inheritanceIndicator: some View {
        Text("photoEditor.preset.inheritingStyle")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 16)
    }

    /// No title — just the slider and its live percentage, side by side (never stacked with a
    /// label above it), matching Adjust's own slider row exactly.
    private var intensityRow: some View {
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { viewModel.presetIntensityPercent },
                    set: { viewModel.presetIntensityPercent = $0 }
                ),
                in: 0...100
            )
            Text("\(Int(viewModel.presetIntensityPercent.rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, PhotoEditorToolTrayMetrics.horizontalPadding)
    }
}

/// A static, bundled thumbnail per `preset.thumbnailAssetName` (rendered once from
/// docs/modules/photo-editor/preset-photo.jpeg via the real `PresetRenderer`, not live per-photo —
/// generating one via `PhotoRenderEngine` for every preset on every photo was slow/unreliable
/// enough in practice (14 concurrent LUT renders) that it stood in the way of the one thing that
/// actually matters: picking a preset correctly applies its LUT to the main preview). Falls back to
/// a stable-per-preset color swatch (never `String.hashValue`, which isn't stable across launches —
/// docs/specs/SPEC-MODIFY-DRAFT.md § 11) + SF Symbol for `Original` and any preset with no bundled
/// thumbnail (e.g. a Preset Tuning Panel-authored custom preset).
private struct PresetThumbnailButton: View {
    let preset: PresetDefinition
    let isSelected: Bool
    let action: () -> Void

    private var displayName: String {
        localizedString(dynamicKey: preset.shortNameKey, defaultValue: preset.shortName)
    }

    private var swatchColor: Color {
        guard !preset.isOriginal else { return Color.secondary.opacity(0.2) }
        let hue = Double(Self.stableHash(preset.id) % 360) / 360
        return Color(hue: hue, saturation: 0.35, brightness: 0.55)
    }

    private var thumbnail: UIImage? {
        PresetThumbnailImageCache.shared.image(named: preset.thumbnailAssetName)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(swatchColor)
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: preset.isOriginal ? "circle.slash" : "camera.filters")
                            .font(.system(size: 18))
                            .foregroundStyle(preset.isOriginal ? Color.secondary : .white.opacity(0.85))
                    }
                }
                .frame(width: PhotoEditorToolTrayMetrics.cellSize, height: PhotoEditorToolTrayMetrics.cellSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white : .white.opacity(0.6))
                    .lineLimit(1)
                    .frame(maxWidth: PhotoEditorToolTrayMetrics.captionMaxWidth)
            }
        }
        .buttonStyle(.plain)
    }

    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for scalar in string.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// Loads a preset's bundled thumbnail JPEG by plain filename — same flat, loose-bundle-resource
/// resolution `CubeLUTLoader` already uses for `.cube` files (this Xcode target's synchronized
/// group flattens every non-Swift resource to the bundle root regardless of source subfolder), not
/// an `Image(_:bundle:)` asset-catalog lookup, since these thumbnails were never added to
/// `Assets.xcassets`. Caches decoded images in memory — there are only 13 of them, each 160×160.
private final class PresetThumbnailImageCache: @unchecked Sendable {
    static let shared = PresetThumbnailImageCache()

    private let lock = NSLock()
    private var cache: [String: UIImage] = [:]

    func image(named assetName: String?) -> UIImage? {
        guard let assetName else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[assetName] { return cached }

        let name = (assetName as NSString).deletingPathExtension
        let ext = (assetName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache[assetName] = image
        return image
    }
}
