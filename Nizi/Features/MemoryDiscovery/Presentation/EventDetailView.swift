//
//  EventDetailView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// The three-tier image model — see docs/sprint/SPRINT-005B-preview.md's follow-up.
/// Shared here so a prefetch call and its matching display request can never drift apart, which
/// is what actually makes the prefetch cache get hit.
fileprivate enum ImageSizing {
    /// Small, cropped, grid cells only.
    static let gridThumbnail = CGSize(width: 160, height: 160)
    /// The viewer's guaranteed floor tier — see the architecture-audit follow-up
    /// ("viewer black-screen fix — guaranteed viewerSeed pipeline"). The audit traced the
    /// black-screen bug to the viewer having no seed of its own for any asset the grid had never
    /// touched: `startCachingImages` is only a best-effort hint, not a guarantee, so a page could
    /// reach `displayPreview`-loaded with literally nothing cached at any size. `viewerSeed` is
    /// requested with a real, awaited `requestThumbnail` call (never just a caching hint) and
    /// preheated farther ahead than `displayPreview`, so the viewer is never dependent on
    /// whatever the grid happened to have already loaded.
    static let viewerSeed = CGSize(width: 400, height: 400)
    /// The full-screen viewer's target-quality tier: fast, "good enough" to view and swipe
    /// through. Deliberately capped well below native device resolution — requesting at full
    /// screen resolution (points × scale, which can exceed 2500px on the long edge) was the
    /// actual cause of "ảnh đầu tiên mất rất lâu hoặc không mở được" on iCloud-backed libraries.
    /// `zoomDetail` (pinch/double-tap zoom, edit, upload) is a reserved third tier — no caller
    /// needs it yet, so there's no API for it until a pinch-zoom feature actually exists.
    static let displayPreview = CGSize(width: 1000, height: 1000)
}

/// One atomic snapshot of "what the full-screen viewer should show," built and validated in a
/// single step at tap time (`EventDetailView.openPreview`) — see
/// docs/sprint/SPRINT-005B-TODO.md's follow-up bug report on `itemCount=0` viewer opens. Driving
/// `.fullScreenCover(item:)` off this (instead of `.fullScreenCover(isPresented:)` plus separate
/// `items`/`index`/`thumbnail` @State vars) makes it structurally impossible for the cover to
/// present with a list that doesn't actually contain the tapped photo.
private struct CurationPreviewPresentation: Identifiable {
    let id = UUID()
    let items: [PhotoCurationItem]
    let openedAssetID: String
    let initialThumbnail: PlatformImage?
    /// This Event's own id — threaded through so `CurationPreviewView`'s `Edit` entry point can
    /// build a real `EditorContext` (PHOTO-EDITOR.md § 4.2).
    let eventId: String
}

/// § 26.1 — "idle / planning / success / failure," nothing more granular (planning is local and
/// fast; no percent-based progress is needed).
private enum AlbumCreationState: Equatable {
    case idle
    case planning
    case success
    case failure
}

/// Cover → event info → selection summary → curated groups → bottom selection bar.
/// Runs Photo Curation automatically the first time this event is opened, scoped to just
/// its own assets — never a library rescan. See docs/sprint/SPRINT-005B.md § 6, § 21–27.
struct EventDetailView: View {
    let event: PhotoEvent
    /// The exact cover `UIImage` `EventCardView` was already displaying at the moment it was
    /// tapped, passed straight through by `EventListView` — see the Hero-image follow-up.
    /// `nil` for entry points that don't have one yet (deep link, previews, or a tap that beat the
    /// card's own cover load).
    let initialHeroImage: PlatformImage?

    init(event: PhotoEvent, initialHeroImage: PlatformImage? = nil) {
        self.event = event
        self.initialHeroImage = initialHeroImage
    }

    @Environment(\.modelContext) private var modelContext
    @State private var sessions: [PhotoSession] = []
    @State private var curationResult: EventCurationResult?
    @State private var curationStatus: CurationStatus = .notStarted
    @State private var progress: (processed: Int, total: Int)?
    @State private var errorMessage: String?
    @State private var albumCreationState: AlbumCreationState = .idle
    @State private var createdAlbumDraft: AlbumDraft?
    @State private var showAlbumCreationFailedAlert = false
    // A single atomic, item-driven payload — not separate `isPresented`/`items`/`index`/
    // `thumbnail` @State vars set one after another. Those could in principle be observed
    // mid-update (e.g. `.fullScreenCover(isPresented:)` reading `previewItems` before a
    // same-scope assignment had "landed"), which is exactly the shape of bug that produced
    // `preview_opened openedAtIndex=0 itemCount=0` on a real device: the cover presented before
    // the item list it needed was actually attached. One struct set in one assignment can't be
    // observed half-updated.
    @State private var previewPresentation: CurationPreviewPresentation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EventCoverView(assetID: event.coverAssetID, assetProvider: assetProvider, initialImage: initialHeroImage)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                eventInfoSection
                selectionSummarySection
                curationContent
            }
            .padding()
        }
        .navigationTitle(event.titleSuggestion)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .task {
            // Warm the cache for the cover plus roughly the first couple of grid screens — not
            // the whole event (which can be 200-300+ assets; "Không prefetch toàn bộ
            // Event"). Doesn't wait on curation, since the event's asset list is already
            // known. (The full-screen preview has its own windowed prefetch — see CurationPreviewView.)
            assetProvider.prefetchThumbnails(assetIDs: initialPrefetchAssetIDs, targetSize: ImageSizing.gridThumbnail, contentMode: .fill, networkAccessAllowed: false)
            await loadSessions()
            await runCurationIfNeeded()
        }
        .onDisappear {
            assetProvider.stopPrefetchingThumbnails(assetIDs: initialPrefetchAssetIDs, targetSize: ImageSizing.gridThumbnail, contentMode: .fill, networkAccessAllowed: false)
        }
        .alert("event.album_creation.failed_title", isPresented: $showAlbumCreationFailedAlert) {
            Button("common.action.retry") { createAlbum() }
            Button("common.action.cancel", role: .cancel) {}
        } message: {
            Text("event.album_creation.failed_message")
        }
        .fullScreenCover(item: $createdAlbumDraft) { draft in
            NavigationStack {
                AlbumDetailView(draft: draft) { updated in
                    await saveUpdatedAlbumDraft(updated)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.action.close") { createdAlbumDraft = nil }
                    }
                }
            }
        }
        .fullScreenCover(item: $previewPresentation) { presentation in
            CurationPreviewView(
                items: presentation.items,
                openedAssetID: presentation.openedAssetID,
                initialThumbnail: presentation.initialThumbnail,
                eventId: presentation.eventId,
                assetProvider: assetProvider,
                onToggle: toggleSelection
            )
        }
    }

    // MARK: - Always-visible event info (available even before/during curation)

    private var eventInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizedString("event.photo_count.value", defaultValue: "\(event.assetCount) photos"))
                .font(.title3.bold())

            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("event.detail.timeline")
                        .font(.headline)
                    ForEach(sessions.sorted(by: { $0.startDate < $1.startDate })) { session in
                        HStack {
                            Text(session.startDate.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(localizedString("event.photo_count.value", defaultValue: "\(session.assetCount) photos"))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("event.detail.why_suggested")
                    .font(.headline)
                ForEach(event.discoveryReasons) { reason in
                    Label(reason.text, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var selectionSummarySection: some View {
        if let curationResult, curationStatus == .completed {
            Text(localizedString("event.detail.selection_summary", defaultValue: "Nizi picked \(curationResult.selectedAssetCount) photos for you"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status-dependent body

    @ViewBuilder
    private var curationContent: some View {
        switch curationStatus {
        case .notStarted, .outdated:
            EmptyView() // .task kicks off curation immediately; nothing to show yet.

        case .processing:
            processingState

        case .completed:
            if let curationResult {
                ForEach(curationResult.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                    CurationGroupSectionView(
                        group: group,
                        assetProvider: assetProvider,
                        onToggle: { toggleSelection(itemID: $0) },
                        onOpenPreview: { item, thumbnail in openPreview(group: group, item: item, initialThumbnail: thumbnail) }
                    )
                }
            }

        case .failed:
            errorState
        }
    }

    private var processingState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("event.curation.processing")
                .font(.subheadline)
            if let progress {
                Text(localizedString("event.curation.progress", defaultValue: "Processed \(progress.processed) / \(progress.total) groups"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(progress.processed), total: Double(max(progress.total, 1)))
            } else {
                ProgressView()
            }
        }
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("event.curation.error.title")
                .font(.subheadline)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button("common.action.retry") {
                Task { await runCuration(forceRecurate: true) }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if let curationResult, curationStatus == .completed {
                Text(localizedString("event.detail.action_bar.selected_count", defaultValue: "\(curationResult.selectedAssetCount) / \(curationResult.sourceAssetCount) photos selected"))
                    .font(.subheadline)
            } else {
                Text(localizedString("event.photo_count.value", defaultValue: "\(event.assetCount) photos"))
                    .font(.subheadline)
            }
            Spacer()
            Button(action: createAlbum) {
                if albumCreationState == .planning {
                    ProgressView()
                } else {
                    Text("event.action.create_album")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(albumCreationState == .planning || curationResult?.selectedAssetCount == 0)
        }
        .padding()
        .background(.bar)
    }

    /// § 26 integration: Create Album → build `AlbumPlanningInput` from this Event's selected
    /// photos → `DefaultAlbumDraftPlanner` → save → open the result. Planning runs off the main
    /// actor (§ 26.2); only the final state update touches UI state, on `@MainActor`.
    private func createAlbum() {
        guard let curationResult else { return }
        let selectedAssetIDs = curationResult.groups.flatMap { group in
            group.items.filter(\.isSelected).map(\.assetID)
        }
        guard !selectedAssetIDs.isEmpty else { return }

        albumCreationState = .planning
        let eventID = event.id.uuidString
        let eventTitle = event.titleSuggestion
        let startDate = event.startDate
        let endDate = event.endDate
        let locationName = event.primaryLocationLabel
        let container = modelContext.container

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let planningPhotos = PHAssetPlanningPhotoAdapter.planningPhotos(assetIDs: selectedAssetIDs, eventId: eventID)
                    let planningEvent = AlbumPlanningEvent(
                        id: eventID, title: eventTitle, startDate: startDate, endDate: endDate,
                        locationName: locationName, latitude: nil, longitude: nil,
                        selectedPhotos: planningPhotos
                    )
                    let input = AlbumPlanningInput(albumTitle: nil, events: [planningEvent])
                    return try await DefaultAlbumDraftPlanner().createDraft(from: input)
                }.value

                let store = SwiftDataAlbumDraftStore(modelContainer: container)
                try await store.save(result.draft)

                albumCreationState = .success
                createdAlbumDraft = result.draft
            } catch {
                NiziLogger.discovery.error("album_creation_failed error=\(String(describing: error), privacy: .public)")
                albumCreationState = .failure
                showAlbumCreationFailedAlert = true
            }
        }
    }

    private func saveUpdatedAlbumDraft(_ draft: AlbumDraft) async {
        do {
            let store = SwiftDataAlbumDraftStore(modelContainer: modelContext.container)
            try await store.updateDraft(draft)
        } catch {
            NiziLogger.discovery.error("album_update_failed")
        }
    }

    // MARK: - Data

    // Held stable for the view's lifetime (not a fresh instance per access) — prefetching only
    // helps if the same PHCachingImageManager instance later serves the actual thumbnail requests.
    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()

    /// Cover + roughly the first couple of grid screens' worth of assets — a deliberate cap,
    /// not the whole event. The rest load on demand as each grid cell scrolls into view.
    private var initialPrefetchAssetIDs: [String] {
        var ids = Array(event.assetIDs.prefix(60))
        if let cover = event.coverAssetID, !ids.contains(cover) {
            ids.append(cover)
        }
        return ids
    }

    private func makeStore() -> SwiftDataMemoryDiscoveryStore {
        SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
    }

    private func loadSessions() async {
        do {
            sessions = try await makeStore().fetchSessions(ids: event.sessionIDs)
        } catch {
            NiziLogger.discovery.error("event_detail_sessions_load_failed")
        }
    }

    private func runCurationIfNeeded() async {
        let store = makeStore()
        if let existing = try? await store.result(for: event.id) {
            curationResult = existing
            curationStatus = existing.status
            if existing.status == .completed,
               existing.algorithmVersion == EventPhotoCurationService.algorithmVersion,
               existing.sourceAssetCount == event.assetIDs.count {
                return
            }
        }
        await runCuration(forceRecurate: false)
    }

    private func runCuration(forceRecurate: Bool) async {
        curationStatus = .processing
        errorMessage = nil
        progress = nil

        let store = makeStore()
        let service = EventPhotoCurationService(
            assetRepository: store,
            sessionRepository: store,
            curationRepository: store,
            analyzer: VisionEventPhotoAnalyzer(assetProvider: assetProvider)
        )

        do {
            let result = try await service.curate(event: event, forceRecurate: forceRecurate) { processed, total in
                Task { @MainActor in
                    progress = (processed, total)
                }
            }
            curationResult = result
            curationStatus = result.status
        } catch {
            curationStatus = .failed
            errorMessage = localizedString("event.curation.error.detail_prefix", defaultValue: "Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Selection

    private func openPreview(group: PhotoCurationGroup, item: PhotoCurationItem, initialThumbnail: PlatformImage?) {
        // Snapshot taken synchronously, at the exact moment of the tap — never a stale/async
        // collection. Flattens *all* groups (in the same order shown in the grid) into one
        // continuous list, so swiping past the last photo in a group continues into the next
        // group instead of stopping — previously this was scoped to just `group.items`.
        guard let curationResult else {
            NiziLogger.discovery.error("preview_open_rejected reason=no_curation_result")
            return
        }
        let snapshot = curationResult.groups
            .sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { $0.items.sorted { $0.sortOrder < $1.sortOrder } }

        guard !snapshot.isEmpty else {
            NiziLogger.discovery.error("preview_open_rejected reason=empty_items groupID=\(group.id, privacy: .public)")
            return
        }
        guard snapshot.contains(where: { $0.assetID == item.assetID }) else {
            NiziLogger.discovery.error("preview_open_rejected reason=tapped_item_missing assetID=\(item.assetID, privacy: .private)")
            return
        }

        let resolvedIndex = snapshot.firstIndex(where: { $0.assetID == item.assetID }) ?? 0
        NiziLogger.discovery.notice("preview_open_requested tappedAssetID=\(item.assetID, privacy: .private) sourceGroupID=\(group.id, privacy: .public) snapshotCount=\(snapshot.count, privacy: .public) resolvedIndex=\(resolvedIndex, privacy: .public) hasThumbnail=\(initialThumbnail != nil, privacy: .public)")

        previewPresentation = CurationPreviewPresentation(
            items: snapshot,
            openedAssetID: item.assetID,
            initialThumbnail: initialThumbnail,
            eventId: event.id.uuidString
        )
    }

    private func toggleSelection(itemID: UUID) {
        guard var result = curationResult else { return }

        for groupIndex in result.groups.indices {
            guard let itemIndex = result.groups[groupIndex].items.firstIndex(where: { $0.id == itemID }) else { continue }
            var item = result.groups[groupIndex].items[itemIndex]
            let newIsSelected = !item.isSelected
            let source: SelectionSource = newIsSelected == item.isSuggested
                ? .systemSuggested
                : (newIsSelected ? .userAdded : .userRemoved)
            item.isSelected = newIsSelected
            item.selectionSource = source
            result.groups[groupIndex].items[itemIndex] = item
            curationResult = result

            Task {
                do {
                    try await makeStore().updateItemSelection(itemID: itemID, isSelected: newIsSelected, source: source)
                } catch {
                    NiziLogger.discovery.error("curation_selection_update_failed")
                }
            }
            return
        }
    }
}

// MARK: - Cover

private struct EventCoverView: View {
    static let heroTargetSize = CGSize(width: 640, height: 440)

    let assetID: String?
    let assetProvider: PhotoAssetProvider

    // Never nils out once set — a failed/slow upgrade just leaves whatever's already on screen.
    @State private var image: PlatformImage?

    init(assetID: String?, assetProvider: PhotoAssetProvider, initialImage: PlatformImage?) {
        self.assetID = assetID
        self.assetProvider = assetProvider
        // Fallback order (Hero-image follow-up): the exact image the card was already showing →
        // a cache hit at this view's own hero size → a cached `viewerSeed` (from the full-screen
        // preview, if this event's cover was ever opened there this session) → a cached
        // `gridThumbnail` (from the curated grid) → nothing, until the async upgrade below lands.
        // Every step here is a synchronous, zero-cost cache lookup — no PhotoKit request is made
        // just to determine the seed.
        let seed = initialImage
            ?? assetID.flatMap { assetProvider.cachedThumbnail(assetID: $0, targetSize: Self.heroTargetSize, contentMode: .fill) }
            ?? assetID.flatMap { assetProvider.cachedThumbnail(assetID: $0, targetSize: ImageSizing.viewerSeed, contentMode: .fit) }
            ?? assetID.flatMap { assetProvider.cachedThumbnail(assetID: $0, targetSize: ImageSizing.gridThumbnail, contentMode: .fill) }
        _image = State(initialValue: seed)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.15))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .clipped()
        .task(id: assetID) {
            guard let assetID else { return }
            do {
                // `networkAccessAllowed: true` — the card's own cover request already needs this
                // (see `EventCardView.loadCover`) for iCloud-optimized libraries, and this is
                // the same situation: a locally-available asset resolves immediately either way,
                // this only adds latency for ones that actually need the network.
                let sharperImage = try await assetProvider.requestThumbnail(
                    assetID: assetID,
                    targetSize: Self.heroTargetSize,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality,
                    contentMode: .fill
                )
                image = sharperImage
            } catch {
                NiziLogger.discovery.error("event_detail_hero_upgrade_failed assetID=\(assetID, privacy: .private) error=\(String(describing: error), privacy: .public)")
            }
        }
    }
}

// MARK: - Curated group section

private struct CurationGroupSectionView: View {
    let group: PhotoCurationGroup
    let assetProvider: PhotoAssetProvider
    let onToggle: (UUID) -> Void
    let onOpenPreview: (PhotoCurationItem, PlatformImage?) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    /// Time first (what usually distinguishes moments within the same day), then day/month —
    /// locale-aware via `Date.FormatStyle` rather than a hardcoded "HH:mm - d/M" pattern, so the
    /// day/month order and separators follow the user's locale instead of always reading dd/M.
    private static func headerDateText(for date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        let day = date.formatted(.dateTime.day().month())
        return "\(time) - \(day)"
    }

    private func toggleAll() {
        let targetSelected = !isAllSelected
        for item in group.items where item.isSelected != targetSelected {
            onToggle(item.id)
        }
    }

    private var isAllSelected: Bool {
        !group.items.isEmpty && group.items.allSatisfy(\.isSelected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.headerDateText(for: group.startDate))
                        .font(.subheadline.bold())
                    Text(localizedString("event.group.selected_summary", defaultValue: "\(group.assetCount) photos · Nizi picked \(group.suggestedCount)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: toggleAll) {
                    Label(
                        isAllSelected ? "event.group.action.deselect_all" : "event.group.action.select_all",
                        systemImage: isAllSelected ? "checkmark.circle.fill" : "circle"
                    )
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(isAllSelected ? Color.accentColor : Color.secondary)
                }
                .accessibilityLabel(isAllSelected ? localizedString("event.group.accessibility.deselect_all", defaultValue: "Deselect all photos in group") : localizedString("event.group.accessibility.select_all", defaultValue: "Select all photos in group"))
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(group.items.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                    CurationThumbnailCell(
                        item: item,
                        assetProvider: assetProvider,
                        onOpenPreview: { thumbnail in onOpenPreview(item, thumbnail) },
                        onToggleSelection: { onToggle(item.id) }
                    )
                }
            }
        }
    }
}

private struct CurationThumbnailCell: View {
    let item: PhotoCurationItem
    let assetProvider: PhotoAssetProvider
    // Passes back whatever thumbnail this cell already has loaded, so the preview it opens can
    // show it immediately instead of starting from nothing — see docs/sprint/SPRINT-005B-preview.md § 3.
    let onOpenPreview: (PlatformImage?) -> Void
    let onToggleSelection: () -> Void

    @State private var image: PlatformImage?

    var body: some View {
        // `Color.clear` is the sizing driver: with `contentMode: .fit`, SwiftUI reliably shrinks
        // it to a square from the grid column's proposed width alone. Driving the square off the
        // ZStack/Image directly (as before) doesn't reliably get a finite proposed height from
        // LazyVGrid, which is what caused cells to overlap/overflow.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // `GeometryReader` here only *reads* the square size `Color.clear.aspectRatio`
                // already resolved — it doesn't participate in deriving it, so it doesn't
                // reintroduce the "no finite proposed height from LazyVGrid" problem noted above.
                GeometryReader { proxy in
                    let checkboxSide = min(proxy.size.width, proxy.size.height) / 3

                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.15))
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenPreview(image) }
                    .overlay(alignment: .bottomTrailing) {
                        // The whole bottom-trailing third of the cell is the checkbox's tap
                        // target, not just the visible icon — a small fixed hit target was still
                        // too easy to miss on a 3-column grid. Sits on top of the photo-tap area
                        // in that corner, so a tap there always hits the checkbox, never the photo.
                        Button(action: onToggleSelection) {
                            Color.clear
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(item.isSelected ? Color.accentColor : Color.white)
                                        .background(Circle().fill(item.isSelected ? Color.white : Color.black.opacity(0.35)))
                                        .padding(4)
                                }
                        }
                        .buttonStyle(.plain)
                        .frame(width: checkboxSide, height: checkboxSide)
                        .accessibilityLabel(item.isSelected ? localizedString("event.photo.accessibility.deselect", defaultValue: "Deselect photo") : localizedString("event.photo.accessibility.select", defaultValue: "Select photo"))
                    }
                }
            }
            .clipped()
            .task(id: item.assetID) {
                image = try? await assetProvider.requestThumbnail(
                    assetID: item.assetID,
                    targetSize: ImageSizing.gridThumbnail,
                    networkAccessAllowed: false,
                    deliveryMode: .highQuality,
                    contentMode: .fill
                )
            }
    }
}

// MARK: - Full-screen preview

/// Three-tier image model — see docs/sprint/SPRINT-005B-preview.md's follow-up: show the grid's
/// already-loaded thumbnail immediately, then upgrade to the `displayPreview` tier (fast, capped
/// size — good enough to view and swipe, not full quality). A window of neighboring assets stays
/// prefetched at that same tier so swiping doesn't re-pay the cost each time.
private struct CurationPreviewView: View {
    @State var items: [PhotoCurationItem]
    /// Deliberately starts at -1 (not `openedAtIndex`) — see the `.task` below for why.
    @State private var currentIndex: Int = -1
    /// Only ever handed to the page the user actually tapped from the grid — see `openedAtIndex`.
    let initialThumbnail: PlatformImage?
    /// This Event's own id — see `CurationPreviewPresentation.eventId`.
    let eventId: String
    let assetProvider: PhotoAssetProvider
    let onToggle: (UUID) -> Void

    /// Resolved from `openedAssetID` against `items`, never assumed — see the `init` below.
    /// `-1` (never a valid TabView tag) means "the requested asset isn't in this list," which the
    /// body treats as a hard error state, not a silent fallback to index 0.
    private let openedAtIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var verticalDragOffset: CGFloat = 0
    @State private var prefetchedAssetIDs: Set<String> = []
    /// True while the current page is pinch/double-tap zoomed in — gates the vertical
    /// swipe-to-dismiss gesture so panning around a zoomed photo can't be misread as a dismiss.
    @State private var isZoomed = false
    /// Drives the `Edit` entry point's `.fullScreenCover` — see PHOTO-EDITOR.md § 4.2.
    @State private var editorContext: EditorContext?

    // MARK: - viewerSeed preheat (guaranteed, not a caching hint — see `ImageSizing.viewerSeed`)

    /// One real, awaited `requestThumbnail` `Task` per in-flight/completed seed request, keyed by
    /// assetID — lets `updateSeedPreheatWindow` skip assets already requested and cancel ones that
    /// fall out of the (wide) seed look-ahead window. `@State` so the same dictionary survives
    /// this view's re-renders instead of resetting every time `body` runs.
    @State private var seedTasks: [String: Task<Void, Never>] = [:]
    @State private var seedWindowAssetIDs: Set<String> = []
    /// Held as `@State` (not a plain `let`) for the same reason `assetProvider` is elsewhere in
    /// this file — a `let` on a `View` struct would recreate the actor on every body re-evaluation,
    /// losing its concurrency-limiting state each time.
    @State private var seedThrottle = ViewerSeedThrottle(maxConcurrent: 3)

    // MARK: - displayPreview task ownership (viewer-level, not page-level)

    /// `displayPreview` requests are owned and tracked *here*, not inside `CurationPreviewPage`.
    /// A page disappearing (SwiftUI tearing down/recycling it as the user swipes, which TabView
    /// does aggressively for pages outside its small live window) used to cancel that page's
    /// `.task`, which cancelled its in-flight `requestThumbnail(displayPreview)` call via
    /// `withTaskCancellationHandler` — wasting real progress and forcing a full re-fetch (visibly
    /// soft again) if the user swiped back. Keyed by assetID so a page just *awaits* whichever
    /// task is already registered for its asset instead of owning one itself; awaiting a `Task`'s
    /// `.value` does not cancel that task if the awaiting context is cancelled.
    @State private var displayPreviewTasks: [String: Task<PlatformImage?, Never>] = [:]
    @State private var displayPreviewWindowAssetIDs: Set<String> = []

    init(
        items: [PhotoCurationItem],
        openedAssetID: String,
        initialThumbnail: PlatformImage?,
        eventId: String,
        assetProvider: PhotoAssetProvider,
        onToggle: @escaping (UUID) -> Void
    ) {
        _items = State(initialValue: items)
        // The caller (`EventDetailView.openPreview`) already validates non-empty +
        // asset-present before ever constructing this view, but this view must never trust that
        // blindly — resolving from `openedAssetID` here (instead of accepting a bare `Int` index
        // the caller computed separately) means an empty or mismatched list can never silently
        // produce "index 0 of nothing." A fallback of `?? 0` here would recreate exactly the bug
        // this replaced, so a miss is `-1` (an explicit error state) instead.
        openedAtIndex = items.isEmpty ? -1 : (items.firstIndex(where: { $0.assetID == openedAssetID }) ?? -1)
        self.initialThumbnail = initialThumbnail
        self.eventId = eventId
        self.assetProvider = assetProvider
        self.onToggle = onToggle
    }

    private var dismissProgress: CGFloat {
        min(abs(verticalDragOffset) / 400, 0.6)
    }

    var body: some View {
        NavigationStack {
            if openedAtIndex < 0 {
                emptyState
            } else {
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    CurationPreviewPage(
                        index: index,
                        item: item,
                        assetProvider: assetProvider,
                        initialThumbnail: index == openedAtIndex ? initialThumbnail : nil,
                        isActive: index == currentIndex,
                        onZoomChanged: { isZoomed = $0 },
                        requestDisplayPreview: { assetID, idx in requestDisplayPreview(assetID: assetID, index: idx) }
                    ) {
                        items[index].isSelected.toggle()
                        onToggle(item.id)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .offset(y: verticalDragOffset)
            .opacity(1 - dismissProgress)
            // Only tracks/reacts when the drag is predominantly vertical, so horizontal swipes
            // are left alone for TabView's own paging gesture to handle.
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !isZoomed else { return }
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        verticalDragOffset = value.translation.height
                    }
                    .onEnded { value in
                        guard !isZoomed else { return }
                        let isVertical = abs(value.translation.height) > abs(value.translation.width)
                        if isVertical, abs(value.translation.height) > 120 {
                            dismiss()
                        } else {
                            withAnimation(.spring(duration: 0.25)) { verticalDragOffset = 0 }
                        }
                    }
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    editButton
                }
            }
            }
        }
        .fullScreenCover(item: $editorContext) { context in
            PhotoEditorView(
                context: context,
                repository: SwiftDataPhotoEditRepository(modelContainer: modelContext.container),
                collectionStyleRepository: SwiftDataCollectionStyleRepository(modelContainer: modelContext.container)
            ) { _ in
                // § 19/§ 21 — same known gap noted on the Album side: refreshing the displayed
                // image for `affectedPhotoIds` needs this event's own photo pipeline
                // (`PhotoAssetProvider`/`PhotoKitAssetProvider`) to become recipe-aware, which is
                // Bước 9's job, not this sprint's entry-point integration.
                editorContext = nil
            }
        }
        .task {
            let openedAssetID = openedAtIndex >= 0 ? items[openedAtIndex].assetID : "none"
            NiziLogger.discovery.notice("preview_opened openedAssetID=\(openedAssetID, privacy: .private) openedAtIndex=\(openedAtIndex, privacy: .public) itemCount=\(items.count, privacy: .public) hasInitialThumbnail=\(initialThumbnail != nil, privacy: .public)")
            guard openedAtIndex >= 0 else {
                NiziLogger.discovery.error("preview_opened_invalid itemCount=\(items.count, privacy: .public)")
                return
            }
            // `TabView(selection:)` can silently fail to render the initial page when the
            // selection's starting `@State` value already equals the page we want shown on
            // first presentation — this was the exact cause of "tap the first photo → nothing
            // shows, tap a different photo → works fine" (the first photo is index 0, which
            // trivially equals a same-value initial state; any other index would have "changed"
            // by luck of the data, masking the bug). Starting at -1 and assigning the real index
            // here guarantees SwiftUI sees a genuine change no matter which photo was tapped.
            currentIndex = openedAtIndex
            updatePrefetchWindow(around: currentIndex)
            updateSeedPreheatWindow(around: currentIndex, previousIndex: currentIndex)
            updateDisplayPreviewTaskWindow(around: currentIndex)
        }
        .onChange(of: currentIndex) { oldIndex, newIndex in
            NiziLogger.discovery.notice("preview_index_changed old=\(oldIndex, privacy: .public) new=\(newIndex, privacy: .public)")
            guard newIndex >= 0 else { return }
            updatePrefetchWindow(around: newIndex)
            updateSeedPreheatWindow(around: newIndex, previousIndex: oldIndex)
            updateDisplayPreviewTaskWindow(around: newIndex)
        }
        .onDisappear {
            if !prefetchedAssetIDs.isEmpty {
                assetProvider.stopPrefetchingThumbnails(assetIDs: Array(prefetchedAssetIDs), targetSize: ImageSizing.displayPreview, contentMode: .fit, networkAccessAllowed: true)
            }
            for task in seedTasks.values { task.cancel() }
            seedTasks.removeAll()
            for task in displayPreviewTasks.values { task.cancel() }
            displayPreviewTasks.removeAll()
        }
    }

    /// § 4.2 — opens Photo Editor on whichever photo is currently on screen, scoped to every
    /// photo in this Event (`items`, the already-flattened full snapshot, not just one group).
    private var editButton: some View {
        Button {
            guard items.indices.contains(currentIndex) else { return }
            let photoId = items[currentIndex].assetID
            editorContext = EditorContext(sourceType: .event, sourceId: eventId, photoId: photoId, photoIds: items.map(\.assetID))
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .accessibilityLabel(Text("photoEditor.editButton.accessibilityLabel"))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("event.viewer.empty.title")
                .font(.subheadline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.action.close") { dismiss() }
            }
        }
    }

    /// Keeps `currentIndex - 1 ... currentIndex + 2` warm via `startCachingImages` — an
    /// optimization hint only, never the source of readiness (see `ImageSizing.viewerSeed` and
    /// `updateSeedPreheatWindow` below, which is what actually guarantees a page has something to
    /// show). Only starts caching for assets newly in range and only stops caching for assets
    /// that just fell out of it — never tears down and rebuilds the whole window on every swipe.
    private func updatePrefetchWindow(around index: Int) {
        let lowerBound = max(0, index - 1)
        let upperBound = min(items.count - 1, index + 2)
        guard lowerBound <= upperBound else { return }

        let newWindow = Set(items[lowerBound...upperBound].map(\.assetID))
        let toStart = newWindow.subtracting(prefetchedAssetIDs)
        let toStop = prefetchedAssetIDs.subtracting(newWindow)

        if !toStart.isEmpty {
            NiziLogger.discovery.notice("preview_prefetch_start count=\(toStart.count, privacy: .public) aroundIndex=\(index, privacy: .public)")
            assetProvider.prefetchThumbnails(assetIDs: Array(toStart), targetSize: ImageSizing.displayPreview, contentMode: .fit, networkAccessAllowed: true)
        }
        if !toStop.isEmpty {
            assetProvider.stopPrefetchingThumbnails(assetIDs: Array(toStop), targetSize: ImageSizing.displayPreview, contentMode: .fit, networkAccessAllowed: true)
        }
        prefetchedAssetIDs = newWindow
    }

    // MARK: - viewerSeed preheat

    /// Keeps `currentIndex - 2 ... currentIndex + 5` seeded — deliberately wider and farther
    /// ahead than the `displayPreview` window above, so a `viewerSeed` is very likely to already
    /// be cached by the time the user actually swipes to a page, regardless of what the grid has
    /// or hasn't rendered. Unlike `updatePrefetchWindow`, this issues real `requestThumbnail`
    /// calls (see `ViewerSeedThrottle`), not just a caching hint, and only cancels a request when
    /// its asset falls out of *this* wider window — never merely for leaving the narrower
    /// `displayPreview` window.
    private func updateSeedPreheatWindow(around index: Int, previousIndex: Int) {
        let lowerBound = max(0, index - 2)
        let upperBound = min(items.count - 1, index + 5)
        guard lowerBound <= upperBound else { return }

        let direction: SwipeDirection = index >= previousIndex ? .forward : .backward
        let newWindow = Set(items[lowerBound...upperBound].map(\.assetID))

        for assetID in seedWindowAssetIDs.subtracting(newWindow) {
            seedTasks[assetID]?.cancel()
            seedTasks[assetID] = nil
        }
        seedWindowAssetIDs = newWindow

        for idx in prioritizedIndices(lower: lowerBound, upper: upperBound, current: index, direction: direction) {
            let item = items[idx]
            guard seedTasks[item.assetID] == nil else { continue }
            guard assetProvider.cachedThumbnail(assetID: item.assetID, targetSize: ImageSizing.viewerSeed, contentMode: .fit) == nil else {
                NiziLogger.discovery.notice("viewer_seed_cache_hit index=\(idx, privacy: .public) assetID=\(item.assetID, privacy: .private) source=preheat")
                continue
            }

            let assetID = item.assetID
            seedTasks[assetID] = Task {
                await seedThrottle.acquire()
                guard !Task.isCancelled else {
                    await seedThrottle.release()
                    return
                }
                let start = Date()
                NiziLogger.discovery.notice("viewer_seed_request_started index=\(idx, privacy: .public) assetID=\(assetID, privacy: .private) targetSize=400x400 source=preheat")
                do {
                    _ = try await assetProvider.requestThumbnail(
                        assetID: assetID,
                        targetSize: ImageSizing.viewerSeed,
                        networkAccessAllowed: true,
                        deliveryMode: .highQuality,
                        contentMode: .fit
                    )
                    let elapsed = Date().timeIntervalSince(start)
                    NiziLogger.discovery.notice("viewer_seed_request_completed index=\(idx, privacy: .public) assetID=\(assetID, privacy: .private) durationSeconds=\(elapsed, format: .fixed(precision: 2), privacy: .public) source=preheat")
                } catch is CancellationError {
                    // Fell out of the seed window before finishing — fine, not an error.
                } catch {
                    NiziLogger.discovery.error("viewer_seed_request_failed index=\(idx, privacy: .public) assetID=\(assetID, privacy: .private) source=preheat")
                }
                await seedThrottle.release()
            }
        }
    }

    /// Orders indices so the swipe direction's forward neighbors are requested before its
    /// trailing ones — e.g. swiping forward from index 5 through a 2...10 window requests
    /// 5,6,7,8,9,10 before 4,3 (the "N+1...N+5" priority the seed window exists for), and
    /// swiping backward does the reverse.
    private func prioritizedIndices(lower: Int, upper: Int, current: Int, direction: SwipeDirection) -> [Int] {
        let all = Array(lower...upper)
        switch direction {
        case .forward:
            return all.filter { $0 >= current }.sorted() + all.filter { $0 < current }.sorted(by: >)
        case .backward:
            return all.filter { $0 <= current }.sorted(by: >) + all.filter { $0 > current }.sorted()
        }
    }

    // MARK: - displayPreview task window (viewer-owned; see `displayPreviewTasks` above)

    /// Same bounds as `updatePrefetchWindow`'s caching hint (N-1...N+2), but this is what actually
    /// guarantees readiness: a real `requestThumbnail(displayPreview)` `Task` per asset in range,
    /// only cancelled when the asset falls out of *this* window — never merely because the page
    /// that happens to be showing it right now was torn down.
    private func updateDisplayPreviewTaskWindow(around index: Int) {
        let lowerBound = max(0, index - 1)
        let upperBound = min(items.count - 1, index + 2)
        guard lowerBound <= upperBound else { return }

        let newWindow = Set(items[lowerBound...upperBound].map(\.assetID))
        for assetID in displayPreviewWindowAssetIDs.subtracting(newWindow) {
            displayPreviewTasks[assetID]?.cancel()
            displayPreviewTasks[assetID] = nil
        }
        displayPreviewWindowAssetIDs = newWindow

        for idx in lowerBound...upperBound {
            requestDisplayPreview(assetID: items[idx].assetID, index: idx)
        }
    }

    /// Returns the existing in-flight/completed `displayPreview` task for `assetID` if one is
    /// already registered (from the window above, or a prior call), otherwise starts and
    /// registers a new one. Idempotent and safe to call from a page directly as a fallback (e.g.
    /// the user swiped somewhere the window management hasn't caught up to yet) — it will just
    /// join the same task a second caller would get.
    @discardableResult
    private func requestDisplayPreview(assetID: String, index: Int) -> Task<PlatformImage?, Never> {
        if let existing = displayPreviewTasks[assetID] {
            return existing
        }

        let task = Task<PlatformImage?, Never> {
            if let cached = assetProvider.cachedThumbnail(assetID: assetID, targetSize: ImageSizing.displayPreview, contentMode: .fit) {
                return cached
            }
            let start = Date()
            NiziLogger.discovery.notice("preview_image_request_started assetID=\(assetID, privacy: .private) purpose=displayPreview targetSize=\(Int(ImageSizing.displayPreview.width), privacy: .public)x\(Int(ImageSizing.displayPreview.height), privacy: .public) index=\(index, privacy: .public)")
            do {
                let image = try await assetProvider.requestThumbnail(
                    assetID: assetID,
                    targetSize: ImageSizing.displayPreview,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality,
                    contentMode: .fit
                )
                let elapsed = Date().timeIntervalSince(start)
                NiziLogger.discovery.notice("preview_display_preview_loaded index=\(index, privacy: .public) assetID=\(assetID, privacy: .private) size=\(image.size.width, privacy: .public)x\(image.size.height, privacy: .public) durationSeconds=\(elapsed, format: .fixed(precision: 2), privacy: .public)")
                return image
            } catch is CancellationError {
                NiziLogger.discovery.notice("preview_display_preview_cancelled index=\(index, privacy: .public) assetID=\(assetID, privacy: .private)")
                return nil
            } catch {
                NiziLogger.discovery.error("preview_display_preview_load_failed index=\(index, privacy: .public) assetID=\(assetID, privacy: .private) error=\(String(describing: error), privacy: .public)")
                return nil
            }
        }
        displayPreviewTasks[assetID] = task
        return task
    }
}

private enum SwipeDirection {
    case forward
    case backward
}

/// Limits how many `viewerSeed` requests are in flight at once, so preheating ahead of a fast
/// swipe never starts a dozen concurrent iCloud downloads. An actor (not a plain counter) because
/// `acquire`/`release` are called from independent, concurrently-running preheat `Task`s.
private actor ViewerSeedThrottle {
    private var activeCount = 0
    private let maxConcurrent: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        activeCount += 1
    }

    func release() {
        activeCount -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}

/// Explicit, comparable representation of which tier is currently on screen — the mechanism that
/// enforces "image quality may only move upward, never backward" (see the architecture-audit
/// follow-up on inconsistent `displayPreview` sharpness). `rawValue` ordering *is* the quality
/// ordering, so a plain integer comparison is the whole guard.
private enum PreviewImageTier: Int, Comparable {
    case gridThumbnail = 0
    case viewerSeed = 1
    case displayPreview = 2

    static func < (lhs: PreviewImageTier, rhs: PreviewImageTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var logName: String {
        switch self {
        case .gridThumbnail: "gridThumbnail"
        case .viewerSeed: "viewerSeed"
        case .displayPreview: "displayPreview"
        }
    }
}

private struct CurationPreviewPage: View {
    // Diagnostic only (log correlation) — not used for layout/identity.
    let index: Int
    let item: PhotoCurationItem
    let assetProvider: PhotoAssetProvider
    /// Whether this page is the one currently centered in the TabView — used only to reset zoom
    /// when the user swipes away, since each page keeps its own zoom `@State` independently.
    let isActive: Bool
    let onZoomChanged: (Bool) -> Void
    /// Joins (or starts) the viewer-owned `displayPreview` task for an asset — see
    /// `CurationPreviewView.requestDisplayPreview`. Deliberately not owned by this page: a page
    /// being torn down/recycled by TabView must not cancel a still-useful in-flight displayPreview fetch.
    let requestDisplayPreview: (String, Int) -> Task<PlatformImage?, Never>
    let onToggleSelection: () -> Void

    // Seeded once from whatever's already available (the grid's loaded thumbnail, or a memory
    // cache hit) so something real is on screen from frame one — never nil, never a placeholder
    // color. Replaced once the displayPreview tier arrives; a failed/cancelled load simply
    // leaves whatever was already showing in place.
    @State private var displayedImage: PlatformImage?
    /// What tier `displayedImage` currently represents — `nil` until the first image is applied.
    /// `applyImage(_:tier:source:)` is the *only* place either of these two is written, and it
    /// refuses any tier lower than this, which is the actual fix for "a previously sharp page
    /// appears soft again."
    @State private var currentTier: PreviewImageTier?
    @State private var showLoadingIndicator = false

    /// Stable per view-*identity* (not per `init` call — SwiftUI reconstructs this struct on
    /// every re-render, but `@State`'s initial value is only actually used the first time this
    /// identity's storage is created). Comparing this across `preview_page_*` log lines is how we
    /// tell "SwiftUI kept my state" from "SwiftUI silently gave me a new instance" on-device.
    @State private var pageInstanceID = UUID()
    @State private var hasLoggedCreation = false

    // Pinch-to-zoom / double-tap-to-zoom / pan-while-zoomed. Deliberately reuses whatever's
    // already in `displayedImage` (the `displayPreview` tier) rather than fetching a separate
    // higher-resolution `zoomDetail` tier — see docs/sprint/SPRINT-005B-preview.md's follow-up,
    // which reserved that tier for exactly this feature but explicitly deferred building it until
    // a zoom UI existed. Revisit only if displayPreview visibly isn't sharp enough once zoomed in.
    @State private var scale: CGFloat = 1
    @State private var pinchStartScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5

    init(
        index: Int,
        item: PhotoCurationItem,
        assetProvider: PhotoAssetProvider,
        initialThumbnail: PlatformImage?,
        isActive: Bool,
        onZoomChanged: @escaping (Bool) -> Void,
        requestDisplayPreview: @escaping (String, Int) -> Task<PlatformImage?, Never>,
        onToggleSelection: @escaping () -> Void
    ) {
        self.index = index
        self.item = item
        self.assetProvider = assetProvider
        self.isActive = isActive
        self.onZoomChanged = onZoomChanged
        self.requestDisplayPreview = requestDisplayPreview
        self.onToggleSelection = onToggleSelection
        // Required init priority (architecture-audit follow-up): displayPreview cache → viewerSeed
        // cache → gridThumbnail (either the grid-tapped `initialThumbnail`, only ever handed to the
        // page the user actually tapped, or a cache hit from the grid having already rendered this
        // cell — neither is relied on as the primary source). `currentTier` is set to match
        // whichever actually won, so `applyImage` immediately knows what NOT to downgrade from.
        let candidates: [(PlatformImage?, PreviewImageTier)] = [
            (assetProvider.cachedThumbnail(assetID: item.assetID, targetSize: ImageSizing.displayPreview, contentMode: .fit), .displayPreview),
            (assetProvider.cachedThumbnail(assetID: item.assetID, targetSize: ImageSizing.viewerSeed, contentMode: .fit), .viewerSeed),
            (initialThumbnail, .gridThumbnail),
            (assetProvider.cachedThumbnail(assetID: item.assetID, targetSize: ImageSizing.gridThumbnail, contentMode: .fill), .gridThumbnail)
        ]
        let resolved = candidates.first { $0.0 != nil }
        _displayedImage = State(initialValue: resolved?.0)
        _currentTier = State(initialValue: resolved?.1)
        NiziLogger.discovery.notice("preview_page_init index=\(index, privacy: .public) hasSeed=\(resolved != nil, privacy: .public)")
        if let image = resolved?.0, let tier = resolved?.1 {
            let pixelWidth = Int(image.cgImage?.width ?? Int(image.size.width * image.scale))
            let pixelHeight = Int(image.cgImage?.height ?? Int(image.size.height * image.scale))
            NiziLogger.discovery.notice("preview_displayed_image_changed index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) tier=\(tier.logName, privacy: .public) pixelWidth=\(pixelWidth, privacy: .public) pixelHeight=\(pixelHeight, privacy: .public) source=initialCache pageInstanceID=none")
        }
    }

    var body: some View {
        // Plain (centered) ZStack for the image itself — a `.bottomTrailing`-aligned ZStack here
        // was pushing letterboxed (e.g. landscape) images down to the bottom-trailing corner
        // instead of centering them. The checkbox is positioned via a separate `.overlay`
        // instead, so it doesn't affect how the image itself is laid out.
        ZStack {
            Color.black
            if let displayedImage {
                GeometryReader { proxy in
                    Image(uiImage: displayedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .contentShape(Rectangle())
                        .gesture(magnifyGesture(containerSize: proxy.size))
                        // `.simultaneousGesture` let TabView's own native horizontal-swipe
                        // recognizer see the same drag at the same time — so panning a zoomed
                        // photo was also read as "swipe to next photo." `.highPriorityGesture`
                        // with a dynamic `including:` mask instead makes this drag fully claim
                        // the touch (blocking TabView's paging) only while actually zoomed in;
                        // at 1x it's `.none` (doesn't participate at all), so normal swipe-between-
                        // photos behavior is untouched.
                        .highPriorityGesture(
                            panGesture(containerSize: proxy.size),
                            including: scale > minScale ? .all : .none
                        )
                        .onTapGesture(count: 2) {
                            toggleDoubleTapZoom()
                        }
                }
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
            } else {
                ProgressView().tint(.white)
            }

            if showLoadingIndicator {
                ProgressView()
                    .tint(.white)
                    .padding(14)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
        }
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            resetZoom()
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: onToggleSelection) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.largeTitle)
                    .foregroundStyle(item.isSelected ? Color.accentColor : Color.white)
                    .background(Circle().fill(item.isSelected ? Color.white : Color.black.opacity(0.35)))
            }
            .padding(24)
            .accessibilityLabel(item.isSelected ? localizedString("event.photo.accessibility.deselect", defaultValue: "Deselect photo") : localizedString("event.photo.accessibility.select", defaultValue: "Select photo"))
        }
        .task(id: item.assetID) {
            NiziLogger.discovery.notice("preview_page_task_start index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) pageInstanceID=\(pageInstanceID.uuidString, privacy: .public)")
            await loadImages()
            if Task.isCancelled {
                NiziLogger.discovery.notice("preview_page_task_cancelled index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) pageInstanceID=\(pageInstanceID.uuidString, privacy: .public)")
            }
        }
        .task {
            // A plain `.task { }` with no `id:` still restarts on every appear/disappear cycle
            // (TabView(.page) cycles pages in and out of its small live window constantly), so
            // `hasLoggedCreation` — not this task's mere presence — is what makes `_created` fire
            // exactly once per true `@State` identity instead of once per appear.
            if !hasLoggedCreation {
                hasLoggedCreation = true
                NiziLogger.discovery.notice("preview_page_created index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) pageInstanceID=\(pageInstanceID.uuidString, privacy: .public)")
            }
            NiziLogger.discovery.notice("preview_page_appeared index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) pageInstanceID=\(pageInstanceID.uuidString, privacy: .public)")
        }
        .onDisappear {
            NiziLogger.discovery.notice("preview_page_disappeared index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) pageInstanceID=\(pageInstanceID.uuidString, privacy: .public)")
        }
    }

    // MARK: - Zoom / pan

    private func magnifyGesture(containerSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = (pinchStartScale * value.magnification).clamped(to: minScale...maxScale)
                scale = newScale
                offset = clampedOffset(offset, scale: newScale, containerSize: containerSize)
                onZoomChanged(scale > minScale)
            }
            .onEnded { _ in
                pinchStartScale = scale
                dragStartOffset = offset
                snapBackIfNeeded(containerSize: containerSize)
            }
    }

    private func panGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard scale > minScale else { return }
                let candidate = CGSize(
                    width: dragStartOffset.width + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
                offset = clampedOffset(candidate, scale: scale, containerSize: containerSize)
            }
            .onEnded { _ in
                dragStartOffset = offset
            }
    }

    private func toggleDoubleTapZoom() {
        withAnimation(.spring(duration: 0.25)) {
            if scale > minScale {
                resetZoom()
            } else {
                scale = doubleTapScale
                pinchStartScale = doubleTapScale
                onZoomChanged(true)
            }
        }
    }

    private func resetZoom() {
        scale = minScale
        pinchStartScale = minScale
        offset = .zero
        dragStartOffset = .zero
        onZoomChanged(false)
    }

    private func snapBackIfNeeded(containerSize: CGSize) {
        guard scale <= minScale else { return }
        withAnimation(.spring(duration: 0.2)) {
            resetZoom()
        }
    }

    /// Keeps the zoomed image from panning past its own edge — standard "can't drag the photo
    /// off screen" clamp, assuming the image is centered and scaled about its own center.
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat, containerSize: CGSize) -> CGSize {
        let maxX = max(0, (containerSize.width * (scale - 1)) / 2)
        let maxY = max(0, (containerSize.height * (scale - 1)) / 2)
        return CGSize(
            width: proposed.width.clamped(to: -maxX...maxX),
            height: proposed.height.clamped(to: -maxY...maxY)
        )
    }

    /// Entry point for this page's `.task(id: item.assetID)`. `ensureSeed()` and
    /// `awaitDisplayPreview()` run *concurrently* (not sequentially, which would needlessly delay
    /// the real `displayPreview` fetch behind the smaller seed one) — safe because every write
    /// goes through `applyImage`, which enforces the upward-only tier invariant regardless of
    /// which finishes first.
    private func loadImages() async {
        async let seed: Void = ensureSeed()
        async let preview: Void = awaitDisplayPreview()
        _ = await (seed, preview)
    }

    /// Guarantees this page shows *something* as fast as possible. Checks the shared cache for a
    /// `viewerSeed` (the guaranteed floor tier) and then a `gridThumbnail` — both effectively free
    /// if `CurationPreviewView`'s wide seed-preheat window already got here first. Only if neither
    /// is cached does it make its own real `viewerSeed` request — this is the case the original
    /// black-screen bug lived in: the user swiping faster than the preheat queue, onto a photo the
    /// grid never rendered either, where previously *nothing* would show until the much larger
    /// `displayPreview` finished. This on-demand request is page-owned (unlike `displayPreview`
    /// below) — losing it to a cancelled page is an acceptable trade since it's only ever a
    /// fallback for a preheat gap, not the primary mechanism.
    private func ensureSeed() async {
        guard displayedImage == nil else { return }

        if let cachedSeed = assetProvider.cachedThumbnail(assetID: item.assetID, targetSize: ImageSizing.viewerSeed, contentMode: .fit) {
            applyImage(cachedSeed, tier: .viewerSeed, source: "cache")
            return
        }
        if let cachedGrid = assetProvider.cachedThumbnail(assetID: item.assetID, targetSize: ImageSizing.gridThumbnail, contentMode: .fill) {
            applyImage(cachedGrid, tier: .gridThumbnail, source: "cache")
            return
        }

        let start = Date()
        NiziLogger.discovery.notice("viewer_seed_request_started index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) targetSize=400x400 source=page")
        do {
            let seedImage = try await assetProvider.requestThumbnail(
                assetID: item.assetID,
                targetSize: ImageSizing.viewerSeed,
                networkAccessAllowed: true,
                deliveryMode: .highQuality,
                contentMode: .fit
            )
            let elapsed = Date().timeIntervalSince(start)
            NiziLogger.discovery.notice("viewer_seed_request_completed index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) durationSeconds=\(elapsed, format: .fixed(precision: 2), privacy: .public) source=page")
            applyImage(seedImage, tier: .viewerSeed, source: "pageSeedRequest")
        } catch is CancellationError {
            // Swiped away before the seed arrived — nothing to do; `awaitDisplayPreview` isn't
            // affected by this task's cancellation since it awaits a viewer-owned `Task`.
        } catch {
            NiziLogger.discovery.error("viewer_seed_request_failed index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) source=page")
        }
    }

    /// Joins the viewer-owned `displayPreview` task for this asset (starting one via
    /// `CurationPreviewView.requestDisplayPreview` if none is registered yet) instead of making
    /// its own request. This is the actual fix for "a previously sharp page appears soft again":
    /// this page's own `.task` can be cancelled by TabView tearing the page down/recycling it
    /// without cancelling the underlying fetch, because awaiting a `Task`'s `.value` does not
    /// cancel that task when the awaiting context is cancelled — the fetch keeps running (and,
    /// once it lands, keeps writing to the shared cache) for whichever page asks for it next.
    private func awaitDisplayPreview() async {
        showLoadingIndicator = false

        // Only show a loading indicator if we're still empty-handed after a short delay — avoids
        // flashing a spinner for the common case where the seed thumbnail is already on screen.
        let indicatorDelay = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, displayedImage == nil else { return }
            showLoadingIndicator = true
        }
        defer { indicatorDelay.cancel() }

        let task = requestDisplayPreview(item.assetID, index)
        if let image = await task.value {
            applyImage(image, tier: .displayPreview, source: "pagePreviewRequest")
        }
        showLoadingIndicator = false
    }

    /// The *only* place `displayedImage`/`currentTier` are written, and the only place
    /// `preview_displayed_image_changed` is logged — deliberately at the point of assignment, not
    /// wherever a PhotoKit request happens to complete, since a completed request doesn't always
    /// win the assignment. Enforces the required invariant: quality only ever moves upward
    /// (`nil → gridThumbnail → viewerSeed → displayPreview`), never backward. A same-tier result
    /// is accepted (harmless — every caller here is already scoped to this page instance's
    /// current `item.assetID` via `.task(id:)`, so a same-tier duplicate can only be a late
    /// cache-hit echo of what's already showing).
    private func applyImage(_ image: PlatformImage, tier: PreviewImageTier, source: String) {
        if let currentTier, tier < currentTier {
            return
        }
        displayedImage = image
        currentTier = tier
        let pixelWidth = Int(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let pixelHeight = Int(image.cgImage?.height ?? Int(image.size.height * image.scale))
        NiziLogger.discovery.notice("preview_displayed_image_changed index=\(index, privacy: .public) assetID=\(item.assetID, privacy: .private) tier=\(tier.logName, privacy: .public) pixelWidth=\(pixelWidth, privacy: .public) pixelHeight=\(pixelHeight, privacy: .public) source=\(source, privacy: .public) pageInstanceID=\(pageInstanceID.uuidString, privacy: .public)")
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
