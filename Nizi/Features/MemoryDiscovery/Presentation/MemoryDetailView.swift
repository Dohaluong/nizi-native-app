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
    @State private var hasLoadedGallerySource = false
    @State private var isShowingAllPhotos = false
    @State private var resolvedPlaceName: String?
    @State private var preview: MemoryPhotoPreview?
    @State private var scrollOffset: CGFloat = 0
    @State private var isDeletingEvent = false
    @State private var showDeleteConfirmation = false
    @State private var isCreatingPhotobook = false
    @State private var createdAlbumDraft: AlbumDraft?
    @State private var showPhotobookCreationError = false
    @State private var isCreatingTrip = false
    @State private var showTripCreationError = false
    /// Lets the screen that pushed this view (`HomeView`) reflect a newly-resolved place on its
    /// own already-rendered card in place, mirroring `TripDetailView`'s `onPlaceResolved` — avoids
    /// Home needing an unconditional reload on every single return just to catch the rare case
    /// this event's place actually changed.
    private let onEventUpdated: (PhotoEvent) -> Void
    private let onEventDeleted: (UUID) async -> Void

    fileprivate static let gallerySpacing: CGFloat = 4
    fileprivate static let maximumRowHeight: CGFloat = 242
    private static let heroHorizontalPadding: CGFloat = 24
    /// The gallery only needs a display-size decode. The full-screen viewer owns the larger
    /// preview tier after the user explicitly opens a photo.
    private static let galleryThumbnailSize = CGSize(width: 480, height: 480)

    /// Hero width is deliberately taken from the UIKit viewport, not a `ScrollView` proposal or
    /// the photo's intrinsic size. This is the final layout authority for this full-bleed screen.
    private var viewportWidth: CGFloat { UIScreen.main.bounds.width }
    private var heroWidth: CGFloat { viewportWidth }
    private var heroHeight: CGFloat { heroWidth * 1.5 }
    private var heroTextWidth: CGFloat { heroWidth - Self.heroHorizontalPadding * 2 }

    init(
        event: PhotoEvent,
        onEventUpdated: @escaping (PhotoEvent) -> Void = { _ in },
        onEventDeleted: @escaping (UUID) async -> Void = { _ in }
    ) {
        self.event = event
        self.onEventUpdated = onEventUpdated
        self.onEventDeleted = onEventDeleted
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                scrollOffset = offset
            }

            if scrollOffset > 24 {
                topBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadSelectedPhotos()
            await enrichPlace()
        }
        .animation(.easeInOut(duration: 0.18), value: scrollOffset > 24)
        .confirmationDialog("Xoá Event này?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Xoá Event", role: .destructive) { deleteEvent() }
        } message: {
            Text("Event sẽ bị xoá khỏi Nizi. Ảnh trong Photos không bị xoá.")
        }
        .alert("Không thể tạo Photobook", isPresented: $showPhotobookCreationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Hãy thử lại sau.")
        }
        .alert("Không thể tạo Trip", isPresented: $showTripCreationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Hãy thử lại sau.")
        }
        .fullScreenCover(item: $createdAlbumDraft) { draft in
            NavigationStack {
                AlbumDetailView(draft: draft) { updated in
                    await saveCreatedPhotobook(updated)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") { createdAlbumDraft = nil }
                    }
                }
            }
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
                usesCompactTimestamp: true,
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
                fixedFrame: CGSize(width: heroWidth, height: heroHeight),
                loadLane: .hero
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: heroWidth, height: heroHeight)

            VStack(alignment: .leading, spacing: 7) {
                Text(heroTitle)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 12) {
                    Text("\(dateRangeText) · \(event.assetCount) ảnh")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer(minLength: 0)
                }
            }
            .frame(width: heroTextWidth, alignment: .leading)
            .padding(.leading, Self.heroHorizontalPadding)
            .padding(.bottom, 30)

        }
        .frame(width: heroWidth, height: heroHeight, alignment: .bottomLeading)
        .clipped()
    }

    private var topBar: some View {
        HStack {
            topBarButton(systemImage: "chevron.left") { dismiss() }
            Spacer()
            topBarOptionsMenu
        }
        .padding(.horizontal, 18)
        .padding(.top, 52)
        .padding(.bottom, 10)
    }

    private var topBarOptionsMenu: some View {
        Menu {
            Button(isShowingAllPhotos ? "Chỉ hiện ảnh đã chọn" : "Hiện tất cả ảnh") {
                isShowingAllPhotos.toggle()
            }
            .disabled(!hasHiddenPhotos)

            Button(isCreatingPhotobook ? "Đang tạo Photobook…" : "Tạo Photobook") {
                createPhotobook()
            }
            .disabled(isCreatingPhotobook || displayedAssetIDs.isEmpty)

            Button(isCreatingTrip ? "Đang tạo Trip…" : "Tạo Trip") {
                createTrip()
            }
            .disabled(isCreatingTrip)

            Divider()
            Button("Xoá Event", role: .destructive) {
                showDeleteConfirmation = true
            }
            .disabled(isDeletingEvent)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Tuỳ chọn kỷ niệm")
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

    private func deleteEvent() {
        guard !isDeletingEvent else { return }
        isDeletingEvent = true
        let eventID = event.id
        let container = modelContext.container

        Task {
            do {
                try await SwiftDataMemoryDiscoveryStore(modelContainer: container).deleteEvent(id: eventID)
                await onEventDeleted(eventID)
                dismiss()
            } catch {
                isDeletingEvent = false
            }
        }
    }

    private func createPhotobook() {
        let assetIDs = displayedAssetIDs
        guard !isCreatingPhotobook, !assetIDs.isEmpty else { return }
        isCreatingPhotobook = true
        let eventID = event.id.uuidString
        let title = event.titleSuggestion
        let startDate = event.startDate
        let endDate = event.endDate
        let locationName = resolvedPlaceName ?? event.primaryLocationLabel
        let container = modelContext.container

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let photos = PHAssetPlanningPhotoAdapter.planningPhotos(assetIDs: assetIDs, eventId: eventID)
                    let planningEvent = AlbumPlanningEvent(
                        id: eventID, title: title, startDate: startDate, endDate: endDate,
                        locationName: locationName, latitude: nil, longitude: nil, selectedPhotos: photos
                    )
                    return try await DefaultAlbumDraftPlanner().createDraft(
                        from: AlbumPlanningInput(albumTitle: nil, events: [planningEvent])
                    )
                }.value
                try await SwiftDataAlbumDraftStore(modelContainer: container).save(result.draft)
                createdAlbumDraft = result.draft
            } catch {
                showPhotobookCreationError = true
            }
            isCreatingPhotobook = false
        }
    }

    private func createTrip() {
        guard !isCreatingTrip else { return }
        isCreatingTrip = true
        let eventID = event.id
        let container = modelContext.container

        Task {
            do {
                // The store returns immediately without a warning when this Event is already
                // part of either a discovered or a user-created Trip.
                _ = try await SwiftDataMemoryDiscoveryStore(modelContainer: container)
                    .createTripIfNeeded(forEventID: eventID)
            } catch {
                showTripCreationError = true
            }
            isCreatingTrip = false
        }
    }

    private func saveCreatedPhotobook(_ draft: AlbumDraft) async {
        try? await SwiftDataAlbumDraftStore(modelContainer: modelContext.container).updateDraft(draft)
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
                                targetSize: Self.galleryThumbnailSize, contentMode: .fill,
                                loadLane: .gallery,
                                onAspectAvailable: { aspect in
                                    // Keep the first measured category stable so later quality
                                    // upgrades do not repeatedly rebuild justified rows.
                                    guard imageAspects[assetID] == nil else { return }
                                    imageAspects[assetID] = Self.masonryAspect(for: aspect)
                                }
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

    /// The visual language intentionally has only three card proportions. Masonry should feel
    /// editorial and calm, rather than exposing every arbitrary camera aspect ratio.
    private static func masonryAspect(for aspect: CGFloat) -> CGFloat {
        let safeAspect = max(aspect, 0.01)
        // Treat small metadata/rounding differences around a square as square too.
        if abs(safeAspect - 1) <= 0.06 { return 1 }
        return safeAspect > 1 ? 3.0 / 2.0 : 2.0 / 3.0
    }

    private var displayedAssetIDs: [String] {
        // Don't briefly materialise every Event photo while the curated selection is still being
        // read from SwiftData. That initial transient gallery was starting PhotoKit work for
        // images the user never sees in the default Memory view.
        guard hasLoadedGallerySource else { return [] }
        let ordered = chronologicalAssetIDs.isEmpty ? event.assetIDs : chronologicalAssetIDs
        guard !isShowingAllPhotos, let selectedAssetIDs else { return ordered }
        return ordered.filter { selectedAssetIDs.contains($0) }
    }

    private var hasHiddenPhotos: Bool {
        guard let selectedAssetIDs else { return false }
        return selectedAssetIDs.count < event.assetIDs.count
    }

    private func loadSelectedPhotos() async {
        defer { hasLoadedGallerySource = true }
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
        if let assets = try? await store.fetchAssets(ids: event.assetIDs) {
            chronologicalAssetIDs = assets.sorted { $0.creationDate < $1.creationDate }.map(\.id)
            imageAspects = Dictionary(uniqueKeysWithValues: assets.compactMap { asset in
                guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return nil }
                return (
                    asset.id,
                    Self.masonryAspect(for: CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight))
                )
            })
        }
        guard let curation = try? await store.result(for: event.id) else { return }
        selectedAssetIDs = Set(curation.orderedSelectedAssetIdentifiers)
    }

    private func enrichPlace() async {
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
        let enriched = await enrichPlaceIfNeeded(for: event, store: store)
        resolvedPlaceName = enriched.eventPlace?.displayName ?? enriched.primaryLocationLabel
        if enriched.eventPlace?.displayName != event.eventPlace?.displayName {
            onEventUpdated(enriched)
        }
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

private enum MemoryDetailImageLoadLane: Equatable {
    case hero
    case gallery

    var loader: PhotoThumbnailRequestLoader {
        switch self {
        case .hero: PhotoThumbnailRequestLoader.memoryHero
        case .gallery: PhotoThumbnailRequestLoader.memoryGallery
        }
    }
}

private struct MemoryDetailImage: View {
    let assetID: String?
    let assetProvider: PhotoAssetProvider
    let targetSize: CGSize
    let contentMode: ThumbnailContentMode
    var fixedFrame: CGSize? = nil
    var loadLane: MemoryDetailImageLoadLane = .gallery
    var onAspectAvailable: ((CGFloat) -> Void)? = nil

    @State private var image: PlatformImage?
    /// `false` while `image` is only the fast local placeholder — mirrors `LovedMemoryCard`'s
    /// same two-tier load (fill the slot instantly, then ease from blurred to sharp) so a gallery
    /// cell never sits on a flat color while its real photo is still downloading from iCloud.
    @State private var isSharp = false
    private static let placeholderSize = CGSize(width: 40, height: 40)

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.14)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .modifier(MemoryDetailImageSizing(contentMode: contentMode, fixedFrame: fixedFrame))
                    .blur(radius: isSharp ? 0 : 14)
                    .animation(.easeInOut(duration: 0.35), value: isSharp)
            }
        }
        .frame(width: fixedFrame?.width, height: fixedFrame?.height)
        .clipped()
        .task(id: assetID) {
            isSharp = false
            guard let assetID else { return }
            if let cached = assetProvider.cachedThumbnail(
                assetID: assetID, targetSize: targetSize, contentMode: contentMode
            ) {
                image = cached
                isSharp = true
                onAspectAvailable?(cached.size.width / max(cached.size.height, 1))
                return
            }

            // Fill the slot immediately with a tiny, local-only preview — near-instant even when
            // the full-quality version below still needs a real iCloud download. Gallery uses
            // `.fit` for this tiny request solely to retain the asset's real aspect ratio, so the
            // justified row settles while blurred previews are visible — never after sharp images.
            let placeholderContentMode: ThumbnailContentMode = loadLane == .gallery ? .fit : contentMode
            if let placeholder = try? await loadLane.loader.thumbnail(
                assetID: assetID,
                targetSize: Self.placeholderSize,
                contentMode: placeholderContentMode,
                networkAccessAllowed: false,
                deliveryMode: .fast
            ) {
                image = placeholder
                onAspectAvailable?(placeholder.size.width / max(placeholder.size.height, 1))
            }

            do {
                let loaded = try await loadLane.loader.thumbnail(
                    assetID: assetID,
                    targetSize: targetSize,
                    contentMode: contentMode,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality
                )
                image = loaded
                isSharp = true
                onAspectAvailable?(loaded.size.width / max(loaded.size.height, 1))
            } catch {
                guard !(error is CancellationError) else { return }
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
