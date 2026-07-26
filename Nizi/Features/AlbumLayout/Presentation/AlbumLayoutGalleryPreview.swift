//
//  AlbumLayoutGalleryPreview.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Every layout in the library, grouped by photo count, each rendered through the same
/// `AlbumPageRenderer` the real Album screens will use — never a bespoke thumbnail view per
/// layout (§ Layout Gallery Preview). Numbered placeholders (1, 2, 3, 4) stand in for real
/// photos so a slot's order is visible at a glance. No Photos Library access, no network, no
/// simulator required — this screen exists specifically so the layout library can be reviewed
/// and tuned from Xcode Previews alone.
struct AlbumLayoutGalleryPreview: View {
    private let repository: AlbumLayoutRepository
    @State private var selectedLayout: AlbumPageLayout?

    init(repository: AlbumLayoutRepository = BundleAlbumLayoutRepository()) {
        self.repository = repository
    }

    private var libraryResult: Result<AlbumLayoutLibrary, Error> {
        Result { try repository.loadLibrary() }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("album.layout.gallery.title")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $selectedLayout) { layout in
                    LayoutDetailPreview(layout: layout)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch libraryResult {
        case let .success(library):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(groupedLayouts(library), id: \.photoCount) { group in
                        photoCountSection(group)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .failure(error):
            errorState(error)
        }
    }

    private func groupedLayouts(_ library: AlbumLayoutLibrary) -> [(photoCount: Int, layouts: [AlbumPageLayout])] {
        Dictionary(grouping: library.layouts, by: \.photoCount)
            .sorted { $0.key < $1.key }
            .map { (photoCount: $0.key, layouts: $0.value.sorted { $0.id < $1.id }) }
    }

    private func photoCountSection(_ group: (photoCount: Int, layouts: [AlbumPageLayout])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizedString("album.layout.photo_count", defaultValue: "\(group.photoCount) photos"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                ForEach(group.layouts) { layout in
                    Button {
                        selectedLayout = layout
                    } label: {
                        layoutCell(layout)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func layoutCell(_ layout: AlbumPageLayout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumPageRenderer(
                layout: layout,
                assignments: numberedAssignments(for: layout),
                photoProvider: NumberedPlaceholderPhotoProvider(),
                showsDebugSlotIds: false
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }

            Text(localizedString(dynamicKey: layout.nameKey, defaultValue: layout.name))
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(layout.id)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(supportedFormatsLabel(layout))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            localizedString(
                "album.layout.gallery.thumbnail_accessibility",
                defaultValue: "\(layout.photoCount)-photo layout, \(localizedString(dynamicKey: layout.nameKey, defaultValue: layout.name))"
            )
        )
    }

    private func supportedFormatsLabel(_ layout: AlbumPageLayout) -> String {
        layout.supportedFormats.map(formatLabel).joined(separator: " · ")
    }

    private func formatLabel(_ format: AlbumPageFormat) -> String {
        switch format {
        case .square: localizedString("album.layout.format.square", defaultValue: "Square")
        case .portrait: localizedString("album.layout.format.portrait", defaultValue: "Portrait")
        case .landscape: localizedString("album.layout.format.landscape", defaultValue: "Landscape")
        }
    }

    private func errorState(_ error: Error) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(describing: error))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One slot per numbered placeholder (`"1"`, `"2"`, ...) in slot order — makes each layout's
/// slot ordering visible in the gallery thumbnail (§ "Dùng ảnh placeholder có số thứ tự").
func numberedAssignments(for layout: AlbumPageLayout) -> [AlbumPhotoAssignment] {
    layout.slots.sorted { $0.order < $1.order }.enumerated().map { index, slot in
        AlbumPhotoAssignment(id: "preview-\(slot.id)", slotId: slot.id, photoId: String(index + 1))
    }
}

struct NumberedPlaceholderPhotoProvider: AlbumSlotPhotoProviding {
    func photoView(reference: AlbumPhotoReference, crop: AlbumPhotoCrop, contentMode: AlbumSlotContentMode) -> some View {
        ZStack {
            Color(.tertiarySystemFill)
            Text(reference.id)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

/// Tap-to-open large preview (§ "Có thể tap một layout để mở preview lớn").
private struct LayoutDetailPreview: View {
    let layout: AlbumPageLayout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AlbumPageRenderer(
                    layout: layout,
                    assignments: numberedAssignments(for: layout),
                    photoProvider: NumberedPlaceholderPhotoProvider(),
                    showsDebugSlotIds: true
                )
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                VStack(spacing: 4) {
                    Text(localizedString(dynamicKey: layout.nameKey, defaultValue: layout.name))
                        .font(.headline)
                    Text(layout.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle(localizedString(dynamicKey: layout.nameKey, defaultValue: layout.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Album Layout Gallery") {
    AlbumLayoutGalleryPreview()
}
