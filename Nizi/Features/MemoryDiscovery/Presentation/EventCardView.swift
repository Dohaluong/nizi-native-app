//
//  EventCardView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI

/// Minimal rebuild from scratch — see the "REBUILD EventCardView FROM SCRATCH" follow-up.
/// 30/70 split (date block / cover photo) using a single `GeometryReader` read fresh on every
/// layout pass — nothing measured is ever written to `@State`, so there's no cached size that can
/// go stale across a re-render or the interactive swipe-back transition. This view owns its own
/// height and rounded clipping; horizontal list padding and inter-card spacing belong to
/// `EventListView`, not here.
struct EventCardView: View {
    let event: PhotoEvent
    let assetProvider: PhotoAssetProvider
    let onCoverLoaded: (PlatformImage) -> Void
    /// Kept separate from the card's navigation action so a heart tap never opens Event Detail.
    let onLoveTapped: (() -> Void)?
    /// Called only for unresolved cards as they approach the viewport; the owner persists and
    /// re-renders the updated Event rather than letting this presentation view touch SwiftData.
    let onPlaceRequested: ((PhotoEvent) -> Void)?

    @State private var coverImage: PlatformImage?

    /// Not `private` — `EventListView` pins every row to this exact value at the call site
    /// too (`.frame(height: EventCardView.cardHeight)`), so there is one single source of
    /// truth for card height instead of two constants that could drift apart.
    static let cardHeight: CGFloat = 140
    private static let dateColumnRatio: CGFloat = 0.3
    private static let coverTargetSize = CGSize(width: 320, height: 320)

    init(
        event: PhotoEvent,
        assetProvider: PhotoAssetProvider,
        onCoverLoaded: @escaping (PlatformImage) -> Void,
        onLoveTapped: (() -> Void)? = nil,
        onPlaceRequested: ((PhotoEvent) -> Void)? = nil
    ) {
        self.event = event
        self.assetProvider = assetProvider
        self.onCoverLoaded = onCoverLoaded
        self.onLoveTapped = onLoveTapped
        self.onPlaceRequested = onPlaceRequested
        // Use an already-cached cover immediately — never start from nil if the image is already
        // in memory (e.g. this event's cover was already loaded elsewhere this session).
        if let coverAssetID = event.coverAssetID {
            _coverImage = State(initialValue: assetProvider.cachedThumbnail(
                assetID: coverAssetID,
                targetSize: Self.coverTargetSize,
                contentMode: .fill
            ))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                dateColumn
                    .frame(width: proxy.size.width * Self.dateColumnRatio, height: proxy.size.height)
                coverColumn
                    .frame(width: proxy.size.width * (1 - Self.dateColumnRatio), height: proxy.size.height)
            }
            // Diagnostic only — never read back by any layout code, purely logged for the
            // real-device audit. Fires on first layout and again if the proposal ever changes,
            // which is exactly what would catch different rows receiving different proposals.
            .onAppear { logRuntimeGeometry(proxy: proxy) }
            .onChange(of: proxy.size) { _, _ in logRuntimeGeometry(proxy: proxy) }
        }
        .frame(height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // Must come *after* `.clipShape`, not before — a shadow applied before clipping gets
        // clipped away along with everything outside the rounded-rect bounds.
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: onLoveTapped == nil ? .combine : .contain)
        .accessibilityLabel(onLoveTapped == nil ? accessibilityLabelText : "")
        .task(id: event.coverAssetID) {
            await loadCover()
        }
        // A merged Event keeps its destination ID but resets place state to `.unresolved`.
        // Keying on that state makes its GPS/place scan run again after the merge.
        .task(id: event.placeResolutionState) {
            guard eventNeedsPlaceResolution(event) else { return }
            onPlaceRequested?(event)
        }
    }

    // MARK: - Runtime geometry diagnostics (audit follow-up — logging only, never fed back into layout)

    private func logRuntimeGeometry(proxy: GeometryProxy) {
        let textColumnWidth = proxy.size.width * Self.dateColumnRatio
        let coverColumnWidth = proxy.size.width * (1 - Self.dateColumnRatio)
        NiziLogger.discovery.notice("event_card_runtime_geometry eventID=\(event.id, privacy: .public) proxyWidth=\(proxy.size.width, format: .fixed(precision: 1), privacy: .public) proxyHeight=\(proxy.size.height, format: .fixed(precision: 1), privacy: .public) textColumnWidth=\(textColumnWidth, format: .fixed(precision: 1), privacy: .public) coverColumnWidth=\(coverColumnWidth, format: .fixed(precision: 1), privacy: .public)")
    }

    // MARK: - Date column (30%)

    private var dateColumn: some View {
        VStack(spacing: 8) {
            Text(monthLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(dayString)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.primary)
            Text(weekdayString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    // MARK: - Cover column (70%)

    /// Root cause of the width/height inconsistency this rebuilds: `.frame(maxWidth: .infinity,
    /// maxHeight: .infinity)` does **not** cap a child that reports a size larger than what it was
    /// proposed — and `.scaledToFill()` on a resizable `Image` does exactly that by design (it
    /// overflows the proposal in one axis to "cover" it, expecting to be cropped afterward). So the
    /// previous `Image().resizable().scaledToFill().frame(maxWidth:.infinity,maxHeight:.infinity)`
    /// let a wide/tall source photo report an *inflated* size, `.clipped()` right after it was
    /// clipping to that same inflated size (a no-op), and the surrounding `ZStack` — which sizes
    /// itself to the union of its children absent other constraints — inherited that inflation,
    /// varying per card by whatever aspect ratio that card's specific cover photo happened to have.
    ///
    /// The fix: a *local* `GeometryReader` establishes one fixed `proxy.size` for this column, and
    /// every child (placeholder, image, gradient, metadata) is given that *exact* `width`/`height`
    /// — never `maxWidth`/`maxHeight` — so nothing here can ever report a size other than what this
    /// container decided. The image can still overflow *its own* frame internally (that's what
    /// `.scaledToFill()` + `.clipped()` on that exact fixed frame is for), but that overflow now
    /// stops at the `Image`'s own explicit frame and never reaches the `ZStack`.
    private var coverColumn: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                if let onLoveTapped {
                    Button(action: onLoveTapped) {
                        Image(systemName: event.isLoved ? "heart.fill" : "heart")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(event.isLoved ? Color.red : Color.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.28), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(event.isLoved ? "Bỏ yêu thích sự kiện" : "Yêu thích sự kiện")
                    .accessibilityHint("Chỉ thay đổi trạng thái yêu thích")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
                }

                metadataOverlay
                    .frame(width: proxy.size.width, alignment: .leading)
                    .background(
                        GeometryReader { metaProxy in
                            Color.clear
                                .onAppear { logMetadataGeometry(metaProxy: metaProxy, coverHeight: proxy.size.height) }
                                .onChange(of: metaProxy.size) { _, _ in logMetadataGeometry(metaProxy: metaProxy, coverHeight: proxy.size.height) }
                        }
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .coordinateSpace(name: coverColumnSpaceName)
        }
    }

    /// Padding lives *inside* this view (around its own content), not applied to it from the call
    /// site after the width-filling `.frame` — padding added after a view has already been forced
    /// to a fixed width just inflates the reported size past that width instead of insetting the
    /// content within it. The trailing photo count sits equally inset from the right edge as the
    /// title/subtitle are from the left because `Spacer` expands to fill whatever's left of the
    /// *same* fixed width the call site proposes to this whole `HStack`.
    private var metadataOverlay: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(event.primaryLocationLabel == nil ? 1 : 2)
                }
            }
            Spacer(minLength: 8)
            Label(event.assetCount.formatted(), systemImage: "photo.on.rectangle")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var coverColumnSpaceName: String { "coverColumnSpace-\(event.id.uuidString)" }

    private func logMetadataGeometry(metaProxy: GeometryProxy, coverHeight: CGFloat) {
        let frame = metaProxy.frame(in: .named(coverColumnSpaceName))
        let distanceToCoverBottom = coverHeight - frame.maxY
        NiziLogger.discovery.notice("event_card_metadata_geometry eventID=\(event.id, privacy: .public) coverHeight=\(coverHeight, format: .fixed(precision: 1), privacy: .public) metadataMinY=\(frame.minY, format: .fixed(precision: 1), privacy: .public) metadataMaxY=\(frame.maxY, format: .fixed(precision: 1), privacy: .public) distanceToCoverBottom=\(distanceToCoverBottom, format: .fixed(precision: 1), privacy: .public)")
    }

    // MARK: - Formatting

    private var titleText: String { event.eventType.displayLabel }

    // Locale-aware component formatting — each block (year/day/month) is derived independently
    // via `Date.FormatStyle` so the card's visual split doesn't hardcode a Vietnamese-only shape.
    private var yearString: String {
        event.startDate.formatted(.dateTime.year())
    }

    private var dayString: String {
        event.startDate.formatted(.dateTime.day())
    }

    private var monthLabel: String {
        let month = Calendar.current.component(.month, from: event.startDate)
        return localizedString("event.card.month", defaultValue: "Tháng \(month)")
    }

    private var weekdayString: String {
        event.startDate.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "vi_VN")))
    }

    private var durationDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: event.startDate)
        let end = calendar.startOfDay(for: event.endDate)
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    private var durationText: String {
        localizedString("event.card.duration.days", defaultValue: "\(durationDays) days")
    }

    private var subtitleText: String {
        if let location = event.eventPlace?.displayName ?? event.primaryLocationLabel {
            return location
        }
        return durationText
    }

    private var accessibilityLabelText: String {
        String(
            localized: "event.card.accessibility.label",
            defaultValue: "\(dayString) \(monthLabel) \(yearString), \(event.assetCount) photos, \(event.eventType.displayLabel)"
        )
    }

    // MARK: - Cover loading

    private func loadCover() async {
        guard let coverAssetID = event.coverAssetID else {
            // `EventDiscoveryEngine.pickCoverAssetID` always returns a real asset ID from the
            // event's own (non-empty) asset list — this should be unreachable in practice.
            NiziLogger.discovery.error("event_card_cover_asset_id_missing eventID=\(event.id, privacy: .public)")
            return
        }
        do {
            let image = try await assetProvider.requestThumbnail(
                assetID: coverAssetID,
                targetSize: Self.coverTargetSize,
                networkAccessAllowed: true,
                deliveryMode: .highQuality,
                contentMode: .fill
            )
            coverImage = image
            onCoverLoaded(image)
        } catch {
            NiziLogger.discovery.error("event_card_cover_load_failed eventID=\(event.id, privacy: .public) assetID=\(coverAssetID, privacy: .private) error=\(String(describing: error), privacy: .public)")
        }
    }
}

extension EventType {
    var displayLabel: String {
        switch self {
        case .trip: localizedString("event.type.trip", defaultValue: "Trip")
        case .dayEvent: localizedString("event.type.day_event", defaultValue: "Day Event")
        case .weekend: localizedString("event.type.weekend", defaultValue: "Weekend")
        case .unknown: localizedString("event.type.unknown", defaultValue: "Event")
        }
    }
}
