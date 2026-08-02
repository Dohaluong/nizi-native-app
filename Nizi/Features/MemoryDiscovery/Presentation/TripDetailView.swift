//
//  TripDetailView.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI
import SwiftData

/// Trip Detail — a full-bleed Hero (cover photo + trip info overlay, not present in the design
/// mock but explicitly requested) above a two-column waterfall gallery adapted from design
/// concept "5a" in docs/design-system/Nizi Home Concepts.dc.html § t5. Gallery layout is scoped
/// here so the fixed Hero remains untouched.
struct TripDetailView: View {
    let trip: TripSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var imageAspects: [String: CGFloat] = [:]
    @State private var galleryWidth: CGFloat = 0
    @State private var photoAssetIDs: [String] = []
    @State private var photoCreationDates: [String: Date] = [:]
    @State private var previewPresentation: TripPreviewPresentation?
    /// Seeded from whatever's already persisted; lazily re-resolved on open by
    /// `enrichPlaceIfNeeded()` when still missing — same "resolve when the user actually looks at
    /// it" idea `EventPlaceEnrichmentService` already uses for Events, reused directly here rather
    /// than reimplemented, since its resolve/cache logic isn't Event-specific.
    @State private var resolvedPlaceName: String?
    /// Lets the screen that pushed this view (`HomeView`/`TripsListView`) reflect a newly-resolved
    /// name on its own already-rendered card in place, instead of that screen doing a full trips
    /// refetch on every return just to catch the rare case something actually changed.
    private let onPlaceResolved: (String) -> Void

    init(trip: TripSummary, onPlaceResolved: @escaping (String) -> Void = { _ in }) {
        self.trip = trip
        self.onPlaceResolved = onPlaceResolved
        _resolvedPlaceName = State(initialValue: trip.displayPlaceName)
    }

    fileprivate static let gallerySpacing: CGFloat = 8
    private static let galleryHorizontalInset: CGFloat = 20
    private static let heroHorizontalPadding: CGFloat = 24

    /// Hero width is deliberately taken from the UIKit viewport, matching `MemoryDetailView`'s
    /// full-bleed hero — the final layout authority for this screen, not a ScrollView proposal.
    private var heroWidth: CGFloat { UIScreen.main.bounds.width }
    private var heroHeight: CGFloat { heroWidth * 1.5 }
    private var heroTextWidth: CGFloat { heroWidth - Self.heroHorizontalPadding * 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 20) {
                    heroSection
                    allPhotosHeader
                    gallery
                }
                .padding(.bottom, 32)
            }

            topBar
        }
        .background(OnboardingTheme.ink)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadPhotos()
            await enrichPlaceIfNeeded()
        }
        .fullScreenCover(item: $previewPresentation) { presentation in
            CurationPreviewView(
                items: presentation.items,
                openedAssetID: presentation.openedAssetID,
                initialThumbnail: assetProvider.cachedThumbnail(
                    assetID: presentation.openedAssetID,
                    targetSize: CGSize(width: 480, height: 480),
                    contentMode: .fill
                ),
                eventId: trip.id.uuidString,
                assetProvider: assetProvider,
                appearance: .lightTimestamp,
                capturedAtByAssetID: photoCreationDates,
                showsSelectionControl: false,
                onToggle: { _ in },
                onAssetReplaced: { itemID, newAssetID in
                    guard let oldAssetID = presentation.items.first(where: { $0.id == itemID })?.assetID else { return }
                    photoAssetIDs = photoAssetIDs.map { $0 == oldAssetID ? newAssetID : $0 }
                    if let oldDate = photoCreationDates[oldAssetID] {
                        photoCreationDates[newAssetID] = oldDate
                    }
                }
            )
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            TripPhotoImage(
                assetID: trip.coverAssetID,
                assetProvider: assetProvider,
                targetSize: CGSize(width: 1_400, height: 2_100),
                contentMode: .fill,
                fixedFrame: CGSize(width: heroWidth, height: heroHeight)
            )

            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                .frame(width: heroWidth, height: heroHeight)

            VStack(alignment: .leading, spacing: 7) {
                Text(heroTitle)
                    .font(.onboardingSerif(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Text(trip.dateRangeText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(heroMetadataText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(width: heroTextWidth, alignment: .leading)
            .padding(.leading, Self.heroHorizontalPadding)
            .padding(.bottom, 30)
        }
        .frame(width: heroWidth, height: heroHeight, alignment: .bottomLeading)
        .clipped()
    }

    private var topBar: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 18)
        .padding(.top, 52)
    }

    private var placeText: String { resolvedPlaceName ?? trip.classification.displayLabel }

    /// Same phrase-variant treatment `MemoryDetailView.heroTitle` already uses for loved Events —
    /// deterministic per trip (not random per render), so reopening the same trip always shows
    /// the same phrasing.
    private var heroTitle: String {
        guard let place = resolvedPlaceName, !place.isEmpty else {
            return "A Trip to Remember"
        }
        let variants = ["A Trip to", "Discovering", "Journey Through", "Exploring"]
        let index = trip.id.uuidString.utf8.reduce(0) { ($0 + Int($1)) % variants.count }
        return "\(variants[index]) \(place)"
    }

    private var heroMetadataText: String {
        let duration = localizedString("event.card.duration.days", defaultValue: "\(trip.durationDays) days")
        let events = localizedString("trip.count.events", defaultValue: "\(trip.eventCount) events")
        let photos = localizedString("trip.count.photos", defaultValue: "\(trip.photoCount) photos")
        return "\(duration) · \(events) · \(photos)"
    }

    // MARK: - All Photos

    private var allPhotosHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("trip.detail.all_photos.title")
                .font(.onboardingSerif(size: 24))
                .foregroundStyle(OnboardingTheme.cream)
            Text(allPhotosSubtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingTheme.cream.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var allPhotosSubtitle: String {
        localizedString(
            "trip.detail.all_photos.subtitle",
            defaultValue: "\(photoAssetIDs.count) photos · \(placeText)"
        )
    }

    // MARK: - 5a waterfall gallery

    private var gallery: some View {
        Group {
            if galleryWidth > 0 {
                LazyVStack(spacing: 20) {
                    ForEach(daySections.indices, id: \.self) { sectionIndex in
                        let section = daySections[sectionIndex]
                        VStack(spacing: 12) {
                            if daySections.count > 1 {
                                TripGalleryDayCard(
                                    label: dayLabel(for: sectionIndex, total: daySections.count),
                                    place: placeText,
                                    date: section.date
                                )
                            }

                            HStack(alignment: .top, spacing: Self.gallerySpacing) {
                                waterfallColumn(0, assets: section.assets)
                                    .frame(width: columnWidth)
                                waterfallColumn(1, assets: section.assets)
                                    .frame(width: columnWidth)
                            }
                        }
                    }
                }
                .padding(.horizontal, Self.galleryHorizontalInset)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { galleryWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        galleryWidth = width
                    }
            }
        }
    }

    private func waterfallColumn(_ column: Int, assets: [TripGalleryAsset]) -> some View {
        let columnAssets = assets.enumerated().compactMap { localIndex, asset in
            localIndex.isMultiple(of: 2) == (column == 0) ? asset : nil
        }
        return LazyVStack(spacing: Self.gallerySpacing) {
            ForEach(columnAssets) { asset in
                Button {
                    openPreview(for: asset.assetID)
                } label: {
                    TripPhotoImage(
                        assetID: asset.assetID,
                        assetProvider: assetProvider,
                        targetSize: CGSize(width: 480, height: 480),
                        contentMode: .fill,
                        onAspectAvailable: { aspect in imageAspects[asset.assetID] = aspect }
                    )
                    .frame(width: columnWidth, height: tileHeight(for: asset.assetID))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                if let quote = quote(afterGlobalAssetIndex: asset.index) {
                    TripGalleryQuoteCard(text: quote.text)
                        .frame(width: columnWidth, height: quote.topic == .family ? 170 : 150)
                }
            }
        }
    }

    private var columnWidth: CGFloat {
        max(0, (galleryWidth - Self.galleryHorizontalInset * 2 - Self.gallerySpacing) / 2)
    }

    private func tileHeight(for assetID: String) -> CGFloat {
        let aspect = max(imageAspects[assetID, default: 0.82], 0.1)
        return min(max(columnWidth / aspect, 120), 280)
    }

    /// A text beat is inserted *after* photo 15, 30, 45… in the trip's chronological sequence.
    /// The data is intentionally independent of a specific photo because Trips currently stores
    /// no captions; themes rotate so a long journey does not read as one-note travel copy.
    private func quote(afterGlobalAssetIndex index: Int) -> TripGalleryQuote? {
        guard (index + 1).isMultiple(of: 15) else { return nil }
        let quoteIndex = (index + 1) / 15 - 1
        return TripGalleryQuote.library[quoteIndex % TripGalleryQuote.library.count]
    }

    private var daySections: [TripGalleryDaySection] {
        let calendar = Calendar.current
        var result: [TripGalleryDaySection] = []
        for (index, assetID) in photoAssetIDs.enumerated() {
            let date = photoCreationDates[assetID] ?? trip.startDate
            let day = calendar.startOfDay(for: date)
            let asset = TripGalleryAsset(index: index, assetID: assetID)
            if result.last?.date == day {
                result[result.count - 1].assets.append(asset)
            } else {
                result.append(TripGalleryDaySection(date: day, assets: [asset]))
            }
        }
        return result
    }

    private func dayLabel(for index: Int, total: Int) -> String {
        if index == 0 { return "Ngày đầu tiên" }
        if index == total - 1 { return "Ngày cuối cùng" }
        return "Ngày thứ \(index + 1)"
    }

    // MARK: - Data

    private func openPreview(for assetID: String) {
        guard photoAssetIDs.contains(assetID) else { return }
        let items = photoAssetIDs.enumerated().map { index, id in
            PhotoCurationItem(
                id: UUID(),
                assetID: id,
                sortOrder: index,
                qualityScore: 0,
                similarityClusterID: "trip-\(trip.id.uuidString)",
                isSuggested: true,
                isSelected: true,
                selectionSource: .systemSuggested
            )
        }
        previewPresentation = TripPreviewPresentation(items: items, openedAssetID: assetID)
    }

    private func loadPhotos() async {
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
        guard let events = try? await store.fetchEvents(ids: trip.eventIDs) else { return }
        let allAssetIDs = events.flatMap(\.assetIDs)
        guard let assets = try? await store.fetchAssets(ids: allAssetIDs) else { return }
        let sortedAssets = assets.sorted { $0.creationDate < $1.creationDate }
        photoAssetIDs = sortedAssets.map(\.id)
        photoCreationDates = Dictionary(uniqueKeysWithValues: sortedAssets.map { ($0.id, $0.creationDate) })
    }

    /// Lazy, on-open place resolution — only runs when nothing usable is already persisted, and
    /// only if the trip actually has a coordinate to resolve (`TripDiscoveryEngine` couldn't
    /// always compute one). Persists the result so reopening this trip, or seeing it on Home/the
    /// Trips list, never re-geocodes the same trip twice.
    private func enrichPlaceIfNeeded() async {
        guard resolvedPlaceName == nil,
              let latitude = trip.primaryLatitude, let longitude = trip.primaryLongitude,
              let coordinate = PhotoCoordinate(latitude: latitude, longitude: longitude)
        else { return }

        let homeCountryCode = Locale.current.regionCode ?? "VN"
        guard let place = await EventPlaceEnrichmentService.shared.resolve(
            coordinate: coordinate, homeCountryCode: homeCountryCode
        ) else { return }

        resolvedPlaceName = place.displayName
        onPlaceResolved(place.displayName)
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
        try? await store.setTripPlace(tripID: trip.id, place: place)
    }
}

private struct TripPreviewPresentation: Identifiable {
    let id = UUID()
    let items: [PhotoCurationItem]
    let openedAssetID: String
}

private struct TripGalleryAsset: Identifiable {
    let index: Int
    let assetID: String
    var id: String { assetID }
}

private struct TripGalleryDaySection {
    let date: Date
    var assets: [TripGalleryAsset]
}

private struct TripGalleryDayCard: View {
    let label: String
    let place: String
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(OnboardingTheme.cream.opacity(0.5))
                .textCase(.uppercase)
            Text(place)
                .font(.onboardingSerif(size: 22, weight: .medium))
                .foregroundStyle(OnboardingTheme.cream)
                .lineLimit(2)
            Text(displayDate)
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingTheme.cream.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "d/M/yyyy"
        return formatter.string(from: date)
    }
}

private struct TripGalleryQuote {
    enum Topic {
        case travel
        case discovery
        case family
        case life
    }

    let topic: Topic
    let text: String

    static let library: [TripGalleryQuote] = [
        .init(topic: .travel, text: "“Đi để thấy thế giới rộng hơn, rồi trở về với trái tim đầy hơn.”"),
        .init(topic: .discovery, text: "“Mỗi ngã rẽ đều có một điều mới để khám phá.”"),
        .init(topic: .family, text: "“Điều đẹp nhất của một chuyến đi là người mình đi cùng.”"),
        .init(topic: .life, text: "“Cuộc sống thường ở trong những khoảnh khắc ta không kịp chuẩn bị.”"),
        .init(topic: .travel, text: "“Có những nơi chỉ cần đến một lần đã muốn nhớ thật lâu.”"),
        .init(topic: .discovery, text: "“Đi chậm một chút để nhìn thấy nhiều hơn.”"),
        .init(topic: .family, text: "“Nhà là nơi những câu chuyện nhỏ luôn được lắng nghe.”"),
        .init(topic: .life, text: "“Ngày bình thường cũng có thể trở thành một kỷ niệm đẹp.”")
    ]
}

private struct TripGalleryQuoteCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.onboardingSerifItalic(size: 14))
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.cream.opacity(0.75))
            .lineSpacing(4)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TripPhotoImage: View {
    let assetID: String?
    let assetProvider: PhotoAssetProvider
    let targetSize: CGSize
    let contentMode: ThumbnailContentMode
    var fixedFrame: CGSize? = nil
    var onAspectAvailable: ((CGFloat) -> Void)? = nil

    @State private var image: PlatformImage?
    /// `false` while `image` is only the fast local placeholder — same two-tier load as
    /// `MemoryDetailImage`: fill the slot instantly, then ease from blurred to sharp once the
    /// real, right-sized image is in, instead of sitting on a flat color during a slow download.
    @State private var isSharp = false
    private static let placeholderSize = CGSize(width: 40, height: 40)

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.14)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .modifier(TripPhotoImageSizing(contentMode: contentMode, fixedFrame: fixedFrame))
                    .blur(radius: isSharp ? 0 : 14)
                    .animation(.easeInOut(duration: 0.35), value: isSharp)
            }
        }
        .frame(width: fixedFrame?.width, height: fixedFrame?.height)
        .clipped()
        .task(id: assetID) {
            isSharp = false
            guard let assetID else { return }
            // A cached Hero/gallery image is already ready to display. Avoid even initiating a
            // second Photos lookup on the UI task — that synchronous setup was enough to hitch a
            // fast tap into Trip Detail after returning from a previous visit.
            if let cached = assetProvider.cachedThumbnail(assetID: assetID, targetSize: targetSize, contentMode: contentMode) {
                image = cached
                isSharp = true
                onAspectAvailable?(cached.size.width / max(cached.size.height, 1))
                return
            }

            // Fill the slot immediately with a tiny, local-only preview — near-instant even when
            // the full-quality version below still needs a real iCloud download.
            if let placeholder = try? await PhotoThumbnailRequestLoader.shared.thumbnail(
                assetID: assetID,
                targetSize: Self.placeholderSize,
                contentMode: contentMode,
                networkAccessAllowed: false,
                deliveryMode: .fast
            ) {
                image = placeholder
            }

            do {
                let loaded = try await PhotoThumbnailRequestLoader.shared.thumbnail(
                    assetID: assetID,
                    targetSize: targetSize,
                    contentMode: contentMode
                )
                image = loaded
                isSharp = true
                onAspectAvailable?(loaded.size.width / max(loaded.size.height, 1))
            } catch {
                guard !(error is CancellationError) else { return }
                NiziLogger.discovery.error("trip_detail_image_load_failed")
            }
        }
    }
}

private struct TripPhotoImageSizing: ViewModifier {
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

#Preview {
    NavigationStack {
        TripDetailView(trip: TripSummary(
            id: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(6 * 86400),
            primaryPlaceName: "Tokyo, Nhật Bản", classification: .internationalTrip,
            eventCount: 5, photoCount: 240, coverAssetID: nil
        ))
    }
}
