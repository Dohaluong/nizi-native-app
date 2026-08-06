//
//  BackgroundScanCoordinator.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation
import SwiftData

/// Owns the First Memory Experience's scan/discover pipeline independent of any View's lifetime,
/// so a scan can keep progressing after the user taps "Dừng lại, xem ngay" and moves on to Home.
/// The first `@Observable` object in this codebase shared across *sibling* views (not just owned
/// by one screen) — instantiated once by `ContentView` (never recreated across onboarding-stage
/// transitions) and injected via `.environment(_:)` to both `UserScanProgressView` and `HomeView`.
/// Precedent for `@Observable` owning long-lived Tasks: `PhotoEditorViewModel`.
///
/// Scope: foreground-only continuation. This app has no `BGTaskScheduler`/`BGProcessingTask`
/// anywhere — `continuationTask` is a plain `Task` that the OS suspends like any other work when
/// the app backgrounds, and picks back up from the persisted `ScanCheckpoint` next time the app
/// is foregrounded (see `resumeBackgroundScanIfNeeded`, called from `HomeView.task`).
@MainActor
@Observable
final class BackgroundScanCoordinator {
    private var modelContainer: ModelContainer?
    private var experienceCoordinator: FirstExperienceCoordinator?
    private let pauseFlag = ScanPauseFlag()

    private(set) var state: FirstExperienceState = .idle
    private(set) var scanPreview: ScanPreviewState = .empty
    private(set) var homeCandidates: [HomeCandidate] = []
    private(set) var isBackgroundScanRunning = false
    /// Bumped once every time a Discover pass finishes as a *result of the background
    /// continuation* completing (not the initial onboarding run) — Home observes this via
    /// `.onChange` to refetch its own Events/Trips `@State` without this class knowing anything
    /// about Home's internal state shape.
    private(set) var discoveryRefreshToken = 0

    private var foregroundTask: Task<MemoryCandidate?, Never>?
    private var continuationTask: Task<Void, Never>?

    /// Must be called once, by `ContentView`, before any dependent View mounts. Idempotent.
    func configure(modelContainer: ModelContainer) {
        guard self.modelContainer == nil else { return }
        self.modelContainer = modelContainer
        self.experienceCoordinator = FirstExperienceCoordinator(modelContainer: modelContainer)
    }

    var scanningCheckpoint: ScanCheckpoint? {
        if case .scanning(let checkpoint) = state { return checkpoint }
        return nil
    }

    var remainingPhotoCount: Int {
        BackgroundScanStatus.remainingCount(for: scanningCheckpoint)
    }

    /// Drives Home's nudge-card visibility.
    var hasIncompleteBackgroundScan: Bool {
        BackgroundScanStatus.hasIncompleteWork(checkpoint: scanningCheckpoint)
    }

    /// The ordinary onboarding flow — same behavior as before this feature existed.
    @discardableResult
    func runForeground(scope: LibraryScanScope) async -> MemoryCandidate? {
        guard let experienceCoordinator else { return nil }
        pauseFlag.reset()
        let task = Task { () -> MemoryCandidate? in
            await experienceCoordinator.run(
                scope: scope, pauseFlag: pauseFlag,
                onStateChange: { [weak self] in self?.state = $0 },
                onScanPreview: { [weak self] in self?.scanPreview = $0 },
                onHomeCandidatesReady: { [weak self] in self?.homeCandidates = $0 }
            )
        }
        foregroundTask = task
        let candidate = await task.value
        foregroundTask = nil
        return candidate
    }

    func requestPause() { pauseFlag.requestPause() }

    /// "Dừng lại, xem ngay" — stop waiting for the whole library and produce a result from
    /// whatever is indexed right now, then detach the rest of the scan into `continuationTask` so
    /// it keeps going after the caller (the onboarding screen) moves on to Home.
    @discardableResult
    func skipAheadToResults(scope: LibraryScanScope) async -> MemoryCandidate? {
        guard let experienceCoordinator else { return nil }
        pauseFlag.requestPause()
        await foregroundTask?.value // let the in-flight batch loop actually stop at its next boundary
        foregroundTask = nil

        let candidate = await experienceCoordinator.discoverScoreAndBuild(
            onStateChange: { [weak self] in self?.state = $0 }
        )
        startContinuationIfNeeded(scope: scope)
        return candidate
    }

    /// Starts (or no-ops if already running) the background continuation loop that keeps
    /// indexing the rest of the library. Called after `skipAheadToResults`, and also from
    /// `HomeView.task` on a cold relaunch that finds a `.running`/`.paused` checkpoint.
    func startContinuationIfNeeded(scope: LibraryScanScope) {
        guard continuationTask == nil, let modelContainer else { return }
        guard scanningCheckpoint?.status != .completed else { return }
        pauseFlag.reset()
        isBackgroundScanRunning = true
        continuationTask = Task { [weak self] in
            await self?.runContinuationLoop(scope: scope, modelContainer: modelContainer)
        }
    }

    /// Home's nudge-card tap target. There's nothing to "restart" if the continuation is already
    /// running — this just (re)starts the loop if it had died (e.g. the app just relaunched and
    /// this is the first time Home asks).
    func prioritizeRemainingScan(scope: LibraryScanScope) {
        startContinuationIfNeeded(scope: scope)
    }

    /// Called from `HomeView.task` — picks a persisted `.running`/`.paused` checkpoint back up
    /// after a cold relaunch that skipped straight to Home (see
    /// `ContentView.determineInitialStage()`). No-ops if a continuation is already live in-memory.
    func resumeBackgroundScanIfNeeded(scope: LibraryScanScope) {
        guard continuationTask == nil, let modelContainer else { return }
        Task { [weak self] in
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContainer)
            guard let checkpoint = try? await store.checkpoint(for: .initial, scopeKey: ScanCheckpoint.scopeKey(for: scope.dateRanges())),
                  checkpoint.status == .running || checkpoint.status == .paused,
                  BackgroundScanStatus.hasIncompleteWork(checkpoint: checkpoint)
            else { return }
            self?.state = .scanning(checkpoint)
            self?.startContinuationIfNeeded(scope: scope)
        }
    }

    private func runContinuationLoop(scope: LibraryScanScope, modelContainer: ModelContainer) async {
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContainer)
        let scanUseCase = ScanPhotoLibraryUseCase(
            assetProvider: PhotoKitAssetProvider(), assetRepository: store, checkpointRepository: store
        )
        do {
            try await scanUseCase.execute(pauseFlag: pauseFlag, dateRanges: scope.dateRanges()) { [weak self] progress in
                self?.state = .scanning(progress)
            }
        } catch {
            NiziLogger.discovery.error("background_scan_continuation_failed error=\(String(describing: error), privacy: .public)")
        }
        continuationTask = nil
        isBackgroundScanRunning = false

        guard let status = scanningCheckpoint?.status, status == .completed || status == .partiallyCompleted else { return }
        await refreshDiscoveryAfterBackgroundScan(modelContainer: modelContainer)
    }

    /// Only re-runs Discover (Events/Trips/Location Intelligence) — deliberately does NOT re-run
    /// Score/Curate/Build a brand-new "First Memory" hero. That pipeline exists specifically to
    /// pick the onboarding hero once; ongoing Home data (Events list, Trips rail) already reads
    /// straight from the store, so a plain Discover pass is all that's needed to reflect the
    /// newly-indexed photos.
    private func refreshDiscoveryAfterBackgroundScan(modelContainer: ModelContainer) async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContainer)
            let discoverUseCase = DiscoverEventsUseCase(
                assetRepository: store, sessionRepository: store, eventRepository: store,
                locationIntelligenceRepository: store, tripRepository: store
            )
            try await discoverUseCase.execute()
            discoveryRefreshToken += 1
            NiziLogger.discovery.info("background_scan_completed_rediscovered")
        } catch {
            NiziLogger.discovery.error("background_scan_rediscover_failed error=\(String(describing: error), privacy: .public)")
        }
    }
}
