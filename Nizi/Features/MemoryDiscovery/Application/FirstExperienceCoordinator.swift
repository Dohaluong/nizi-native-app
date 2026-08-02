//
//  FirstExperienceCoordinator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import SwiftData

/// UI-facing state for the First Memory Experience (docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md
/// § 5.1). Not persisted — rebuilt fresh every time `FirstExperienceCoordinator.run` is called.
enum FirstExperienceState: Equatable {
    case idle
    case scanning(ScanCheckpoint?)
    case discovering
    /// Carries the real discovered-event count (SPRINT-INITIAL-SCAN-MEMORY-JOURNEY-HOME § 11:
    /// "chỉ khi count là dữ liệu thật") — known the moment discovery finishes, so no extra
    /// plumbing is needed beyond passing it through this existing transition.
    case curating(eventCount: Int)
    case ready(MemoryCandidate)
    case empty
    case failed(String)
}

/// Orchestrates Scan → Discover → Score → Curate → Build for the First Memory Experience.
/// Never replaces `ScanPhotoLibraryUseCase`/`DiscoverEventsUseCase`/`EventPhotoCurationService` —
/// it only calls them in the right order and turns the result into a `MemoryCandidate`
/// (§ 5: "Coordinator không thay thế các engine hiện có").
@MainActor
final class FirstExperienceCoordinator {
    /// Below this many selected photos, a curated Event isn't worth showing as a First Memory
    /// even if its pre-curation score cleared the threshold.
    private static let minimumSelectedPhotoCount = 3
    /// Only the top-ranked events are worth the cost of running Vision curation on.
    private static let maximumCandidatesToTry = 3

    private let modelContainer: ModelContainer
    private let scoring: MemoryCandidateScoring
    private let memoryBuilder: MemoryBuilder
    private let minimumScore: Double
    private let placeResolver: PhotoPlaceResolving
    private let placeCache: PhotoPlaceCaching
    private let fastHomeDetector: FastHomeCandidateDetecting

    init(
        modelContainer: ModelContainer,
        scoring: MemoryCandidateScoring = DefaultMemoryCandidateScoring(),
        memoryBuilder: MemoryBuilder = MemoryBuilder(),
        minimumScore: Double = MemoryCandidateScoringConfig.firstMemoryMinimumScore,
        placeResolver: PhotoPlaceResolving = ApplePhotoPlaceResolver(),
        placeCache: PhotoPlaceCaching = InMemoryPhotoPlaceCache(),
        fastHomeDetector: FastHomeCandidateDetecting = DefaultFastHomeCandidateDetector()
    ) {
        self.modelContainer = modelContainer
        self.scoring = scoring
        self.memoryBuilder = memoryBuilder
        self.minimumScore = minimumScore
        self.placeResolver = placeResolver
        self.placeCache = placeCache
        self.fastHomeDetector = fastHomeDetector
    }

    /// Runs the whole pipeline once. Returns the built `MemoryCandidate`, or `nil` if scanning
    /// paused mid-way (the caller should let the user resume) or no event cleared the threshold.
    ///
    /// `onScanPreview`/`onHomeCandidatesReady` are best-effort side observations of the scan —
    /// neither is ever awaited by the scan loop itself (SPRINT-INITIAL-SCAN-MEMORY-JOURNEY-HOME
    /// § 24: "scanner never awaits user home selection"). The caller (`UserScanProgressView`) owns
    /// presenting the Home Confirmation Card and persisting the user's choice directly — this
    /// coordinator only ever *offers* candidates, once, and moves on.
    @discardableResult
    func run(
        scope: LibraryScanScope,
        pauseFlag: ScanPauseFlag,
        onStateChange: @escaping (FirstExperienceState) -> Void,
        onScanPreview: @escaping (ScanPreviewState) -> Void = { _ in },
        onHomeCandidatesReady: @escaping ([HomeCandidate]) -> Void = { _ in }
    ) async -> MemoryCandidate? {
        NiziLogger.discovery.info("first_experience_started")

        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContainer)

        do {
            // A user-confirmed Home always wins — don't spend any effort computing Fast
            // candidates the view could never offer anyway (SPEC § 21/§ 31).
            let skipFastHome = (try? await store.fetchHome())?.source == .userConfirmed

            // MARK: Scan
            let scanUseCase = ScanPhotoLibraryUseCase(
                assetProvider: PhotoKitAssetProvider(),
                assetRepository: store,
                checkpointRepository: store
            )
            NiziLogger.discovery.info("photo_scan_started")
            var latestCheckpoint: ScanCheckpoint?
            var previewState = ScanPreviewState.empty
            var observationAccumulator = FastHomeObservationAccumulator()
            var homeCandidatesEmitted = false

            try await scanUseCase.execute(pauseFlag: pauseFlag, dateRanges: scope.dateRanges()) { progress in
                latestCheckpoint = progress
                onStateChange(.scanning(progress))
            } onBatch: { batch in
                previewState = ScanPreviewAccumulator.reduce(previous: previewState, batch: batch)
                onScanPreview(previewState)

                guard !skipFastHome, !homeCandidatesEmitted else { return }
                observationAccumulator.add(records: batch)
                let candidates = self.fastHomeDetector.candidates(from: observationAccumulator.allObservations, config: .default)
                guard FastHomeCandidateReadiness.isReady(candidates: candidates, config: .default) else { return }

                homeCandidatesEmitted = true
                NiziLogger.discovery.info("fast_home_candidates_ready count=\(candidates.count, privacy: .public)")
                Task { @MainActor in
                    let resolved = await self.resolvePlaceNames(for: Array(candidates.prefix(3)))
                    onHomeCandidatesReady(resolved)
                }
            }

            guard let finalStatus = latestCheckpoint?.status,
                  finalStatus == .completed || finalStatus == .partiallyCompleted
            else {
                // Paused — the view keeps its resume affordance and calls `run` again.
                return nil
            }
            NiziLogger.discovery.info("photo_scan_completed")

            return await discoverScoreAndBuild(onStateChange: onStateChange)
        } catch {
            NiziLogger.discovery.error("first_experience_failed error=\(String(describing: error), privacy: .public)")
            onStateChange(.failed(error.localizedDescription))
            return nil
        }
    }

    /// Runs Discover→Score→Curate→Build on whatever is CURRENTLY in the Local Memory Index — no
    /// assumption the scan is complete. Used by `run()` above (after a completed scan) and by
    /// `BackgroundScanCoordinator.skipAheadToResults` (deliberately on a still-partial index —
    /// Discover/Score/Curate have no dependency on scan completeness; they only read whatever
    /// `assetRepository.fetchClusterableAssets()` currently returns).
    @discardableResult
    func discoverScoreAndBuild(onStateChange: @escaping (FirstExperienceState) -> Void) async -> MemoryCandidate? {
        let startedAt = Date()
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContainer)

        do {
            // MARK: Discover
            onStateChange(.discovering)
            let discoverUseCase = DiscoverEventsUseCase(
                assetRepository: store,
                sessionRepository: store,
                eventRepository: store,
                locationIntelligenceRepository: store,
                tripRepository: store
            )
            let events = try await discoverUseCase.execute()

            guard !events.isEmpty else {
                onStateChange(.empty)
                NiziLogger.discovery.info("first_experience_completed result=empty")
                return nil
            }

            // MARK: Score
            let ranked = events
                .map { event in (event: event, score: scoring.score(event: event)) }
                .sorted { $0.score > $1.score }

            for candidate in ranked {
                NiziLogger.discovery.info("memory_candidate_scored eventID=\(candidate.event.id, privacy: .public) score=\(candidate.score, format: .fixed(precision: 1), privacy: .public)")
            }

            let topCandidates = Array(ranked.prefix(Self.maximumCandidatesToTry))

            // MARK: Curate + build
            onStateChange(.curating(eventCount: events.count))
            for candidate in topCandidates where candidate.score >= minimumScore {
                if let memory = await curateAndBuild(candidate: candidate.event, score: candidate.score, store: store) {
                    try await store.save(memory)
                    NiziLogger.discovery.info("first_memory_selected eventID=\(candidate.event.id, privacy: .public) score=\(candidate.score, format: .fixed(precision: 1), privacy: .public)")
                    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    NiziLogger.discovery.info("first_memory_ready durationMs=\(durationMs, privacy: .public)")
                    onStateChange(.ready(memory))
                    return memory
                }
            }

            // Every top candidate either failed curation, under-selected, or never cleared the
            // threshold — try the safe fallback on the single highest-scored event before giving up.
            if let top = ranked.first, top.score >= minimumScore,
               let fallback = memoryBuilder.buildFallback(event: top.event) {
                try await store.save(fallback)
                NiziLogger.discovery.info("first_memory_ready durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) fallback=true")
                onStateChange(.ready(fallback))
                return fallback
            }

            onStateChange(.empty)
            NiziLogger.discovery.info("first_experience_completed result=empty")
            return nil
        } catch {
            NiziLogger.discovery.error("first_experience_failed error=\(String(describing: error), privacy: .public)")
            onStateChange(.failed(error.localizedDescription))
            return nil
        }
    }

    private func curateAndBuild(candidate event: PhotoEvent, score: Double, store: SwiftDataMemoryDiscoveryStore) async -> MemoryCandidate? {
        let service = EventPhotoCurationService(
            assetRepository: store,
            sessionRepository: store,
            curationRepository: store,
            analyzer: VisionEventPhotoAnalyzer(assetProvider: PhotoKitAssetProvider())
        )
        do {
            let result = try await service.curate(event: event, forceRecurate: false) { _, _ in }
            guard result.selectedAssetCount >= Self.minimumSelectedPhotoCount else { return nil }
            return memoryBuilder.build(event: event, curation: result, score: score)
        } catch {
            NiziLogger.discovery.error("first_experience_curation_failed eventID=\(event.id, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Only the (at most 3) candidates actually offered to the user get reverse-geocoded — never
    /// every cluster (SPEC § 18). Same cluster-first, cache-by-coordinate-bucket, geocode-once
    /// pattern `TravelClassificationService` already uses; a candidate whose geocode fails just
    /// keeps `displayName == nil` — the card falls back to a coordinate string (§ 33).
    private func resolvePlaceNames(for candidates: [HomeCandidate]) async -> [HomeCandidate] {
        var resolved: [HomeCandidate] = []
        resolved.reserveCapacity(candidates.count)
        for candidate in candidates {
            var candidate = candidate
            if let coordinate = PhotoCoordinate(latitude: candidate.centerLatitude, longitude: candidate.centerLongitude) {
                let key = PhotoPlaceCacheKey(coordinate: coordinate)
                if let cached = await placeCache.place(for: key) {
                    candidate.displayName = cached.displayName
                } else {
                    do {
                        let place = try await placeResolver.resolvePlace(for: coordinate)
                        await placeCache.store(place, for: key)
                        candidate.displayName = place.displayName
                    } catch {
                        NiziLogger.discovery.error("fast_home_candidate_geocode_failed error=\(String(describing: error), privacy: .public)")
                    }
                }
            }
            resolved.append(candidate)
        }
        return resolved
    }
}
