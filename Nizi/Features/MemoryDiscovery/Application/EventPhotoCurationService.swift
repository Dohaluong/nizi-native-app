//
//  EventPhotoCurationService.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Orchestrates Photo Curation for exactly one Event — never touches the library
/// scan, Local Memory Index rebuild, or global Event Discovery. See docs/sprint/SPRINT-005B.md § 3.2.
///
/// Reuses a cached result whenever it's still valid (§ 19); only runs the Vision pipeline when
/// there's no result yet, the event's asset count changed, the algorithm version moved on,
/// or the caller explicitly asks to re-curate (§ 20).
final class EventPhotoCurationService {
    /// Bump when the scoring/clustering/selection logic changes meaningfully enough that
    /// existing cached results should be considered stale.
    ///
    /// 1 → 2: SPRINT-SMART-EVENT-HIGHLIGHTS.md — Quality Gate, improved local near-duplicate
    /// clustering, Global Duplicate Suppression, stronger Favorite priority, lightweight temporal
    /// diversity in the event-wide trim. Safe to bump only because manual-selection preservation
    /// (§ 5-8) and asset-fingerprint cache identity (§ 9-11) shipped first — every Event recurates
    /// lazily on next open, and any prior userAdded/userRemoved choice survives the recurate.
    ///
    /// 2 → 3: SPRINT-NEXT § 22-23 — flat `maxAutoSelectedPerMoment` ceiling on top of the ratio
    /// cap, fixing a real ~500-photo Event over-selecting to ~400. Existing cached results must be
    /// invalidated so users who already scanned before this fix actually see it.
    static let algorithmVersion = 3

    private let assetRepository: LocalAssetRepository
    private let sessionRepository: PhotoSessionRepository
    private let curationRepository: EventCurationRepository
    private let analyzer: EventPhotoAnalyzer
    /// Overridable so Curation Diagnostics can construct a differently-tuned instance for live
    /// threshold experimentation (SPRINT-SMART-EVENT-HIGHLIGHTS.md § 21) without touching the
    /// production default.
    private let config: EventPhotoCurationEngine.Configuration

    init(
        assetRepository: LocalAssetRepository,
        sessionRepository: PhotoSessionRepository,
        curationRepository: EventCurationRepository,
        analyzer: EventPhotoAnalyzer,
        config: EventPhotoCurationEngine.Configuration = .default
    ) {
        self.assetRepository = assetRepository
        self.sessionRepository = sessionRepository
        self.curationRepository = curationRepository
        self.analyzer = analyzer
        self.config = config
    }

    func curate(
        event: PhotoEvent,
        forceRecurate: Bool = false,
        onProgress: @escaping (_ processedSessions: Int, _ totalSessions: Int) -> Void
    ) async throws -> EventCurationResult {
        // Fetched unconditionally — even on a forced recurate — so any manual selection on the
        // existing result can still be captured and preserved below. Before this fix, a forced
        // recurate (the "Thử lại" retry button) never even looked at the prior result, so it
        // silently discarded any userAdded/userRemoved choices; see SPRINT-SMART-EVENT-HIGHLIGHTS.md § 5-8.
        let cached = try await curationRepository.result(for: event.id)
        if !forceRecurate, let cached, Self.isCacheValid(cached, for: event) {
            return cached
        }

        let overrides = cached.map(EventPhotoCurationEngine.captureUserOverrides(from:)) ?? .empty

        try await curationRepository.markStatus(photoEventID: event.id, status: .processing, errorMessage: nil)

        do {
            let assets = try await assetRepository.fetchAssets(ids: event.assetIDs)
            let sessions = try await sessionRepository.fetchSessions(ids: event.sessionIDs)

            let analyzed = await analyzer.analyze(assets: assets, sessions: sessions, onProgress: onProgress)
            let analyzedPhotosByAssetID = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.assetID, $0) })

            let localGroups = EventPhotoCurationEngine.curateLocally(analyzedPhotos: analyzed, config: config)
            let globalCandidateAssetIDs = EventPhotoCurationEngine.globalDedupCandidateAssetIDs(from: localGroups, config: config)
            let globalDuplicateGroups = analyzer.globalDuplicateGroups(
                candidateAssetIDs: globalCandidateAssetIDs,
                similarityThreshold: config.globalSimilarityThreshold
            )

            var result = EventPhotoCurationEngine.finalize(
                localGroups: localGroups,
                analyzedPhotosByAssetID: analyzedPhotosByAssetID,
                globalDuplicateGroups: globalDuplicateGroups,
                photoEventID: event.id,
                sourceAssetCount: analyzed.count,
                sourceAssetFingerprint: SourceAssetFingerprint.compute(assetIDs: event.assetIDs),
                algorithmVersion: Self.algorithmVersion,
                config: config
            )
            result = EventPhotoCurationEngine.applyPreservedUserOverrides(to: result, overrides: overrides)
            result.completedAt = Date()

            try await curationRepository.saveResult(result)

            let metrics = CurationDiagnosticsMetrics.compute(
                result: result,
                isFavoriteByAssetID: analyzedPhotosByAssetID.mapValues(\.metrics.isFavorite)
            )
            NiziLogger.discovery.info("event_curation_completed eventAssetCount=\(event.assetIDs.count, privacy: .public) selected=\(result.selectedAssetCount, privacy: .public)")
            NiziLogger.discovery.info("event_curation_metrics source=\(metrics.sourcePhotoCount, privacy: .public) usable=\(metrics.usablePhotoCount, privacy: .public) localClusters=\(metrics.localClusterCount, privacy: .public) localSelected=\(metrics.localSelectedCount, privacy: .public) globalDuplicateSuppressed=\(metrics.globalDuplicateSuppressedCount, privacy: .public) finalSelected=\(metrics.finalSelectedCount, privacy: .public) favoriteSource=\(metrics.favoriteSourceCount, privacy: .public) favoriteSelected=\(metrics.favoriteSelectedCount, privacy: .public) userOverride=\(metrics.userOverrideCount, privacy: .public)")

            return result
        } catch {
            try? await curationRepository.markStatus(
                photoEventID: event.id,
                status: .failed,
                errorMessage: error.localizedDescription
            )
            NiziLogger.discovery.error("event_curation_failed")
            throw error
        }
    }

    /// The one place cache validity is decided — `sourceAssetFingerprint`, not `sourceAssetCount`,
    /// is the real identity signal (§ 9-11): count alone missed "same count, different assets."
    /// `static` and internal (not `private`) so `EventDetailView` can call the exact same check
    /// instead of re-implementing it inline and risking the two drifting apart.
    static func isCacheValid(_ result: EventCurationResult, for event: PhotoEvent) -> Bool {
        result.status == .completed
            && result.algorithmVersion == Self.algorithmVersion
            && result.sourceAssetFingerprint == SourceAssetFingerprint.compute(assetIDs: event.assetIDs)
    }
}
