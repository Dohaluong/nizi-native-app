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
    static let algorithmVersion = 1

    private let assetRepository: LocalAssetRepository
    private let sessionRepository: PhotoSessionRepository
    private let curationRepository: EventCurationRepository
    private let analyzer: EventPhotoAnalyzer

    init(
        assetRepository: LocalAssetRepository,
        sessionRepository: PhotoSessionRepository,
        curationRepository: EventCurationRepository,
        analyzer: EventPhotoAnalyzer
    ) {
        self.assetRepository = assetRepository
        self.sessionRepository = sessionRepository
        self.curationRepository = curationRepository
        self.analyzer = analyzer
    }

    func curate(
        event: PhotoEvent,
        forceRecurate: Bool = false,
        onProgress: @escaping (_ processedSessions: Int, _ totalSessions: Int) -> Void
    ) async throws -> EventCurationResult {
        if !forceRecurate,
           let cached = try await curationRepository.result(for: event.id),
           isValid(cached, for: event) {
            return cached
        }

        try await curationRepository.markStatus(photoEventID: event.id, status: .processing, errorMessage: nil)

        do {
            let assets = try await assetRepository.fetchAssets(ids: event.assetIDs)
            let sessions = try await sessionRepository.fetchSessions(ids: event.sessionIDs)

            let analyzed = await analyzer.analyze(assets: assets, sessions: sessions, onProgress: onProgress)

            var result = EventPhotoCurationEngine.curate(
                analyzedPhotos: analyzed,
                photoEventID: event.id,
                sourceAssetCount: analyzed.count,
                algorithmVersion: Self.algorithmVersion
            )
            result.completedAt = Date()

            try await curationRepository.saveResult(result)

            NiziLogger.discovery.info("event_curation_completed eventAssetCount=\(event.assetIDs.count, privacy: .public) selected=\(result.selectedAssetCount, privacy: .public)")

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

    private func isValid(_ result: EventCurationResult, for event: PhotoEvent) -> Bool {
        result.status == .completed
            && result.algorithmVersion == Self.algorithmVersion
            && result.sourceAssetCount == event.assetIDs.count
    }
}
