//
//  MemoryDetailView.swift
//  Nizi
//
//  Created by Codex on 7/31/26.
//

import SwiftUI
import SwiftData
import UIKit

/// A presentation-first view of an Event the user has loved. It deliberately reads directly from
/// `PhotoEvent`: Love does not create, curate, or depend on a `MemoryCandidate`.
struct MemoryDetailView: View {
    let event: PhotoEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var imageAspects: [String: CGFloat] = [:]
    @State private var galleryWidth: CGFloat = 0
    @State private var selectedAssetIDs: Set<String>?
    @State private var chronologicalAssetIDs: [String] = []
    @State private var isShowingAllPhotos = false
    @State private var resolvedPlaceName: String?
    @State private var preview: MemoryPhotoPreview?

    fileprivate static let gallerySpacing: CGFloat = 4
    fileprivate static let maximumRowHeight: CGFloat = 242
    private static let heroHorizontalPadding: CGFloat = 24

    /// Hero width is deliberately taken from the UIKit viewport, not a `ScrollView` proposal or
    /// the photo's intrinsic size. This is the final layout authority for this full-bleed screen.
    private var viewportWidth: CGFloat { UIScreen.main.bounds.width }
    private var heroWidth: CGFloat { viewportWidth }
    private var heroHeight: CGFloat { heroWidth * 1.5 }
    private var heroTextWidth: CGFloat { heroWidth - Self.heroHorizontalPadding * 2 }

    init(event: PhotoEvent) {
        self.event = event
        _resolvedPlaceName = State(initialValue: event.eventPlace?.displayName ?? event.primaryLocationLabel)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 20) {
                    heroSection
                    gallery
                }
                .padding(.bottom, 32)
            }

            topBar
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadSelectedPhotos()
            await enrichPlace()
        }
        .fullScreenCover(item: $preview) { preview in
            AlbumPhotoPreviewView(
                photos: preview.photos,
                albumId: event.id.uuidString,
                allAlbumPhotoIds: preview.assetIDs,
                pageId: "memory-\(event.id.uuidString)",
                startIndex: preview.openedIndex,
                editorSourceType: .event,
                allowsHidingPhotos: false,
                onPhotoReplaced: { oldPhotoID, newPhoto in
                    replaceMemoryPhoto(oldPhotoID: oldPhotoID, with: newPhoto.sourceIdentifier)
                },
                onDismiss: {
                    self.preview = nil
                }
            )
            // AlbumDetail injects this provider at its navigation boundary. Memory opens the
            // same viewer from a different feature tree, so it must explicitly supply the real
            // Photos implementation; otherwise AlbumPhotoView falls back to its Preview/test
            // mock provider and no library image can be rendered.
            .environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            MemoryDetailImage(
                assetID: event.coverAssetID ?? event.assetIDs.first,
                assetProvider: assetProvider,
                targetSize: CGSize(width: 1_400, height: 2_100),
                contentMode: .fill,
                fixedFrame: CGSize(width: heroWidth, height: heroHeight)
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: heroWidth, height: heroHeight)

            VStack(alignment: .leading, spacing: 7) {
                Text(heroTitle)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Text(dateRangeText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: heroTextWidth, alignment: .leading)
            .padding(.leading, Self.heroHorizontalPadding)
            .padding(.bottom, 30)

        }
        .frame(width: heroWidth, height: heroHeight, alignment: .bottomLeading)
        .clipped()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            topBarButton(systemImage: "chevron.left") {
                dismiss()
            }
            Spacer(minLength: 8)
            Text(heroTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Button(isShowingAllPhotos ? "Chỉ hiện ảnh đã chọn" : "Hiện tất cả ảnh") {
                    isShowingAllPhotos.toggle()
                }
                .disabled(!hasHiddenPhotos)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.5), in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 52)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func topBarButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var gallery: some View {
        LazyVStack(spacing: Self.gallerySpacing) {
            ForEach(justifiedRows(for: galleryWidth)) { row in
                HStack(spacing: Self.gallerySpacing) {
                    ForEach(row.assetIDs, id: \.self) { assetID in
                        Button {
                            preview = MemoryPhotoPreview(assetIDs: displayedAssetIDs, openedAssetID: assetID)
                        } label: {
                            MemoryDetailImage(
                                assetID: assetID, assetProvider: assetProvider,
                                targetSize: CGSize(width: 900, height: 900), contentMode: .fill,
                                onAspectAvailable: { aspect in imageAspects[assetID] = aspect }
                            )
                            .frame(width: row.width(for: assetID), height: row.height)
                            .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Self.gallerySpacing)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { galleryWidth = proxy.size.width - Self.gallerySpacing * 2 }
                    .onChange(of: proxy.size.width) { _, width in
                        galleryWidth = width - Self.gallerySpacing * 2
                    }
            }
        }
    }

    private var heroTitle: String {
        guard let place = resolvedPlaceName, !place.isEmpty else {
            switch event.eventType {
            case .trip: return "A Trip to Remember"
            case .weekend: return "A Weekend to Remember"
            case .dayEvent: return "A Day to Remember"
            case .unknown: return "A Memory to Remember"
            }
        }
        let variants: [String]
        switch event.eventType {
        case .trip:
            variants = ["A Trip to", "Discovering", "Journey Through", "Exploring"]
        case .dayEvent:
            variants = ["A Day in", "Moments in", "Discovering", "Exploring"]
        case .weekend:
            variants = ["A Weekend in", "Weekend Escape to", "Slow Days in", "Exploring"]
        case .unknown:
            variants = ["Memories from", "Discovering", "Exploring"]
        }
        let index = event.id.uuidString.utf8.reduce(0) { ($0 + Int($1)) % variants.count }
        return "\(variants[index]) \(place)"
    }

    private var dateRangeText: String {
        let calendar = Calendar(identifier: .gregorian)
        let start = event.startDate
        let end = event.endDate

        guard !calendar.isDate(start, inSameDayAs: end) else {
            return formatted(start, pattern: "d MMM yyyy")
        }
        if calendar.component(.year, from: start) == calendar.component(.year, from: end),
           calendar.component(.month, from: start) == calendar.component(.month, from: end) {
            return "\(formatted(start, pattern: "d"))–\(formatted(end, pattern: "d")) \(formatted(end, pattern: "MMM yyyy"))"
        }
        return "\(formatted(start, pattern: "d MMM yyyy")) – \(formatted(end, pattern: "d MMM yyyy"))"
    }

    private func formatted(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private func justifiedRows(for width: CGFloat) -> [MemoryMasonryRow] {
        guard width > 0 else { return [] }
        var result: [MemoryMasonryRow] = []
        var current: [String] = []
        var currentAspectSum: CGFloat = 0

        for assetID in displayedAssetIDs {
            let aspect = imageAspects[assetID, default: 1]
            current.append(assetID)
            currentAspectSum += aspect
            let rowHeight = (width - CGFloat(current.count - 1) * Self.gallerySpacing)
                / max(currentAspectSum, 0.01)

            // Keep adding images until the justified row is at most 242 pt high. This makes a
            // tall portrait shrink into a denser 2–4 image row rather than becoming a huge tile.
            if current.count == 4 || rowHeight <= Self.maximumRowHeight {
                result.append(MemoryMasonryRow(
                    assetIDs: current, aspects: aspects(for: current),
                    aspectSum: currentAspectSum, containerWidth: width
                ))
                current = []
                currentAspectSum = 0
            }
        }
        if !current.isEmpty {
            result.append(MemoryMasonryRow(
                assetIDs: current, aspects: aspects(for: current),
                aspectSum: currentAspectSum, containerWidth: width
            ))
        }
        return result
    }

    private func aspects(for assetIDs: [String]) -> [String: CGFloat] {
        Dictionary(uniqueKeysWithValues: assetIDs.map { ($0, imageAspects[$0, default: 1]) })
    }

    private var displayedAssetIDs: [String] {
        let ordered = chronologicalAssetIDs.isEmpty ? event.assetIDs : chronologicalAssetIDs
        guard !isShowingAllPhotos, let selectedAssetIDs else { return ordered }
        return ordered.filter { selectedAssetIDs.contains($0) }
    }

    private var hasHiddenPhotos: Bool {
        guard let selectedAssetIDs else { return false }
        return selectedAssetIDs.count < event.assetIDs.count
    }

    private func loadSelectedPhotos() async {
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
        if let assets = try? await store.fetchAssets(ids: event.assetIDs) {
            chronologicalAssetIDs = assets.sorted { $0.creationDate < $1.creationDate }.map(\.id)
        }
        guard let curation = try? await store.result(for: event.id) else { return }
        selectedAssetIDs = Set(curation.orderedSelectedAssetIdentifiers)
    }

    private func enrichPlace() async {
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
        let enriched = await enrichPlaceIfNeeded(for: event, store: store)
        resolvedPlaceName = enriched.eventPlace?.displayName ?? enriched.primaryLocationLabel
    }

    /// The shared Album viewer returns a newly exported Photos asset after an edit. Keep Memory's
    /// curated selection pointing at that asset so reopening this journey never falls back to the
    /// pre-edit image.
    private func replaceMemoryPhoto(oldPhotoID: String, with newPhotoID: String) {
        chronologicalAssetIDs = chronologicalAssetIDs.map { $0 == oldPhotoID ? newPhotoID : $0 }
        selectedAssetIDs = selectedAssetIDs.map { selected in
            var updated = selected
            updated.remove(oldPhotoID)
            updated.insert(newPhotoID)
            return updated
        }

        Task {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            guard let curation = try? await store.result(for: event.id),
                  let item = curation.groups
                    .flatMap(\.items)
                    .first(where: { $0.assetID == oldPhotoID }) else { return }
            do {
                try await store.updateItemAsset(itemID: item.id, newAssetLocalIdentifier: newPhotoID)
            } catch {
                NiziLogger.discovery.error("memory_detail_asset_update_failed")
            }
        }
    }
}

private struct MemoryMasonryRow: Identifiable {
    let assetIDs: [String]
    let aspects: [String: CGFloat]
    let aspectSum: CGFloat
    let containerWidth: CGFloat

    var id: String { assetIDs.joined(separator: "|") }
    var height: CGFloat {
        min(
            (containerWidth - CGFloat(max(assetIDs.count - 1, 0)) * MemoryDetailView.gallerySpacing) / max(aspectSum, 0.01),
            MemoryDetailView.maximumRowHeight
        )
    }

    func width(for assetID: String) -> CGFloat {
        height * aspects[assetID, default: 1]
    }
}

/// A self-contained presentation payload makes opening the viewer atomic: it always receives the
/// tapped photo together with the exact chronological sequence currently visible in the gallery.
private struct MemoryPhotoPreview: Identifiable {
    let id = UUID()
    let assetIDs: [String]
    let openedAssetID: String

    var photos: [AlbumPhotoAssignment] {
        assetIDs.enumerated().map { index, assetID in
            AlbumPhotoAssignment(
                id: "memory-preview-\(index)-\(assetID)",
                slotId: "memory-slot-\(index)",
                photoId: assetID
            )
        }
    }

    var openedIndex: Int {
        assetIDs.firstIndex(of: openedAssetID) ?? 0
    }
}

private struct MemoryDetailImage: View {
    let assetID: String?
    let assetProvider: PhotoAssetProvider
    let targetSize: CGSize
    let contentMode: ThumbnailContentMode
    var fixedFrame: CGSize? = nil
    var onAspectAvailable: ((CGFloat) -> Void)? = nil

    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.14)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .modifier(MemoryDetailImageSizing(contentMode: contentMode, fixedFrame: fixedFrame))
            }
        }
        .frame(width: fixedFrame?.width, height: fixedFrame?.height)
        .clipped()
        .task(id: assetID) {
            guard let assetID else { return }
            image = assetProvider.cachedThumbnail(assetID: assetID, targetSize: targetSize, contentMode: contentMode)
            do {
                let loaded = try await assetProvider.requestThumbnail(
                    assetID: assetID,
                    targetSize: targetSize,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality,
                    contentMode: contentMode
                )
                image = loaded
                onAspectAvailable?(loaded.size.width / max(loaded.size.height, 1))
            } catch {
                NiziLogger.discovery.error("memory_detail_image_load_failed")
            }
        }
    }
}

private struct MemoryDetailImageSizing: ViewModifier {
    let contentMode: ThumbnailContentMode
    let fixedFrame: CGSize?

    func body(content: Content) -> some View {
        if let fixedFrame {
            content
                .scaledToFill()
                .frame(width: fixedFrame.width, height: fixedFrame.height)
                .clipped()
        } else {
            content.aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
        }
    }
}
