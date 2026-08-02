//
//  UserScanProgressView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// Runs the First Memory Experience pipeline (scan → discover → score → curate → build) via
/// `FirstExperienceCoordinator`, then hands the built `MemoryCandidate` (or `nil` if none cleared
/// the threshold) back to `ContentView`. Never shows Scan/Index/Event/Curation terminology — see
/// docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md § 3.2/§ 11.
///
/// Redesigned by SPRINT-INITIAL-SCAN-MEMORY-JOURNEY-HOME into a "Memory Journey": the year the
/// scanner is currently passing through, a small favorite-first photo preview, and — once enough
/// GPS samples exist — an inline Home Confirmation Card. The scanner itself never pauses for any
/// of this (§ 24); `scanPreview`/`homeCandidates` are best-effort observations fed by
/// `FirstExperienceCoordinator`'s new `onScanPreview`/`onHomeCandidatesReady` callbacks.
struct UserScanProgressView: View {
    let scope: LibraryScanScope
    let onComplete: (MemoryCandidate?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(BackgroundScanCoordinator.self) private var coordinator
    @State private var isHomeCardDismissed = false
    @State private var isMapPickerPresented = false
    @State private var previousYear: Int?

    var body: some View {
        ZStack {
            OnboardingSolidBackground()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    OnboardingEyebrowLabel(titleKey: "discovering.eyebrow.traveling_to")

                    yearBlock
                    photoPreviewRow

                    Text("discovering.hero.title")
                        .font(.onboardingSerifItalic(size: 19))
                        .foregroundStyle(OnboardingTheme.cream.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)

                    if let secondaryMessage {
                        Text(secondaryMessage)
                            .font(.subheadline)
                            .foregroundStyle(OnboardingTheme.cream.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    if let checkpoint = coordinator.scanningCheckpoint, let total = checkpoint.totalAssetsEstimated, total > 0 {
                        VStack(spacing: 8) {
                            Text(localizedString("discovering.stats.photos_indexed", defaultValue: "\(checkpoint.processedCount) photos indexed"))
                                .font(.system(size: 13))
                                .foregroundStyle(OnboardingTheme.cream.opacity(0.6))
                            ProgressView(value: Double(checkpoint.processedCount), total: Double(total))
                                .tint(OnboardingTheme.accent)
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView().tint(OnboardingTheme.cream)
                    }

                    if case .failed(let message) = coordinator.state {
                        VStack(spacing: 12) {
                            Text(localizedString("scan.progress.error.failed", defaultValue: "Survey failed: \(message)"))
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                            OnboardingPillButton(titleKey: "common.action.retry", action: runFlow)
                        }
                    }

                    if coordinator.scanningCheckpoint?.status == .running {
                        OnboardingTextLink(titleKey: "scan.progress.action.pause") { coordinator.requestPause() }
                    } else if coordinator.scanningCheckpoint?.status == .paused {
                        OnboardingPillButton(titleKey: "scan.progress.action.resume", action: runFlow)
                    }

                    if coordinator.scanningCheckpoint?.status == .running || coordinator.scanningCheckpoint?.status == .paused {
                        OnboardingTextLink(titleKey: "scan.progress.action.skip_ahead") { skipAhead() }
                    }

                    if showHomeCard {
                        HomeConfirmationCardView(
                            candidates: coordinator.homeCandidates,
                            onSelect: { candidate in Task { await confirmHome(candidate) } },
                            onChooseOnMap: {
                                NiziLogger.discovery.info("home_map_selected")
                                isMapPickerPresented = true
                            },
                            onSkip: {
                                NiziLogger.discovery.info("home_confirmation_skipped")
                                withAnimation { isHomeCardDismissed = true }
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.3), value: showHomeCard)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isMapPickerPresented) {
            HomeMapPickerView(
                onConfirm: { latitude, longitude in
                    isMapPickerPresented = false
                    Task { await confirmHomeFromMap(latitude: latitude, longitude: longitude) }
                },
                onCancel: { isMapPickerPresented = false }
            )
        }
        .onAppear {
            if coordinator.isBackgroundScanRunning {
                // Reopened (e.g. from Home's nudge card) while a background continuation is
                // already live — just observe it, don't start a second concurrent runForeground.
                NiziLogger.discovery.info("scan_progress_reopened_while_background_running")
            } else {
                NiziLogger.discovery.info("initial_scan_started")
                runFlow()
            }
        }
    }

    // MARK: - Year block

    @ViewBuilder
    private var yearBlock: some View {
        if let year = coordinator.scanPreview.currentYear {
            VStack(spacing: 4) {
                if let previousYear {
                    Text(String(previousYear))
                        .font(.onboardingSerif(size: 17))
                        .foregroundStyle(OnboardingTheme.cream.opacity(0.3))
                }
                Text(String(year))
                    .font(.onboardingSerif(size: 48, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.cream)
                Text(relativeYearText(year))
                    .font(.system(size: 14))
                    .foregroundStyle(OnboardingTheme.cream.opacity(0.5))
            }
            .id(year)
            .transition(.opacity.animation(.easeOut(duration: 0.2)))
            .onChange(of: year) { oldValue, _ in
                previousYear = oldValue
            }
        }
    }

    private func relativeYearText(_ year: Int) -> String {
        let currentYear = Calendar.current.component(.year, from: Date())
        if year == currentYear {
            return localizedString("discovering.year.this_year", defaultValue: "This year")
        }
        return localizedString("discovering.year.years_ago", defaultValue: "\(currentYear - year) years ago")
    }

    // MARK: - Photo preview

    @ViewBuilder
    private var photoPreviewRow: some View {
        let thumbnails = Array(coordinator.scanPreview.candidates.prefix(3))
        if !thumbnails.isEmpty {
            HStack(spacing: 6) {
                ForEach(thumbnails) { candidate in
                    ScanPreviewPhotoCell(assetID: candidate.assetID)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .id(candidate.assetID)
                }
            }
            .transition(.opacity.animation(.easeOut(duration: 0.25)))
        }
    }

    // MARK: - State

    private var showHomeCard: Bool {
        !coordinator.homeCandidates.isEmpty && !isHomeCardDismissed
    }

    private var secondaryMessage: String? {
        switch coordinator.state {
        case .scanning:
            return localizedString("discovering.message.scanning", defaultValue: "Reliving years gone by…")
        case .discovering:
            return localizedString("discovering.message.discovering", defaultValue: "Connecting nearby moments…")
        case .curating(let eventCount):
            return localizedString("discovering.phase.curating_with_count", defaultValue: "Found \(eventCount) moments. Picking out the standouts…")
        default:
            return nil
        }
    }

    // MARK: - Actions

    private func runFlow() {
        Task {
            let candidate = await coordinator.runForeground(scope: scope)
            switch coordinator.state {
            case .ready, .empty:
                NiziLogger.discovery.info("initial_scan_completed")
                onComplete(candidate)
            default:
                // Paused (waiting for the resume tap above) or failed (retry button above) — stay put.
                break
            }
        }
    }

    private func skipAhead() {
        NiziLogger.discovery.info("scan_skip_ahead_requested")
        Task {
            let candidate = await coordinator.skipAheadToResults(scope: scope)
            // Deliberately unconditional: "Dừng lại, xem ngay" must proceed to Home immediately
            // even if this partial index didn't clear the First-Memory threshold — Home has its
            // own empty state, and the nudge card keeps the remaining work visible.
            onComplete(candidate)
        }
    }

    private func confirmHome(_ candidate: HomeCandidate) async {
        NiziLogger.discovery.info("home_candidate_selected")
        let anchor = HomeAnchor(
            clusterID: UUID(),
            centerLatitude: candidate.centerLatitude,
            centerLongitude: candidate.centerLongitude,
            homeScore: candidate.score,
            confidence: .high,
            source: .userConfirmed,
            placeName: candidate.displayName
        )
        await persist(anchor)
    }

    private func confirmHomeFromMap(latitude: Double, longitude: Double) async {
        var placeName: String?
        if let coordinate = PhotoCoordinate(latitude: latitude, longitude: longitude),
           let place = try? await ApplePhotoPlaceResolver().resolvePlace(for: coordinate) {
            placeName = place.displayName
        }
        let anchor = HomeAnchor(
            clusterID: UUID(),
            centerLatitude: latitude,
            centerLongitude: longitude,
            homeScore: 1.0,
            confidence: .high,
            source: .userConfirmed,
            placeName: placeName
        )
        await persist(anchor)
    }

    private func persist(_ anchor: HomeAnchor) async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            try await store.confirmUserHome(anchor)
        } catch {
            NiziLogger.discovery.error("home_confirmation_persist_failed error=\(String(describing: error), privacy: .public)")
        }
        withAnimation { isHomeCardDismissed = true }
    }
}

/// Plain PhotoKit thumbnail loading, same idiom as `MemoryViewerView`'s `MemoryPhotoCell` — best
/// effort, `.fast`/no-network delivery since these are just background-scan preview candidates
/// (SPEC § 29: bounded, small target size, opportunistic).
private struct ScanPreviewPhotoCell: View {
    let assetID: String

    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var image: PlatformImage?
    private static let targetSize = CGSize(width: 400, height: 400)

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: assetID) {
            image = assetProvider.cachedThumbnail(assetID: assetID, targetSize: Self.targetSize, contentMode: .fill)
            image = try? await assetProvider.requestThumbnail(
                assetID: assetID, targetSize: Self.targetSize,
                networkAccessAllowed: false, deliveryMode: .fast, contentMode: .fill
            )
        }
    }
}

#Preview {
    UserScanProgressView(scope: .fullLibrary, onComplete: { _ in })
        .environment(BackgroundScanCoordinator())
        .modelContainer(
            for: [
                MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
                MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
                MDMemoryCandidate.self,
                MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
            ],
            inMemory: true
        )
}
