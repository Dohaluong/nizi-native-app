//
//  AlbumDraftPlanningPreview.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Debug-only screen for exercising the Album Draft Planner — no Photos Library access, entirely
/// synthetic `AlbumPlanningPhoto` data. Three separate tabs (docs/specs/SPEC-MODIFY-DRAFT.md
/// § 13) so the "does this look like a real, varied Album" experience isn't crowded out by the
/// narrow technical edge cases, or vice versa:
///
/// - **Varied Album** — 8–12 mock Events (2–6 photos each), regenerable, seedable.
/// - **Edge Cases** — the original 3 scenarios (6 photos/1 Spread, 13 photos/1 Event, singleton
///   Event merge).
/// - **Layout Library** — the existing `AlbumLayoutGalleryPreview`, for geometry inspection.
struct AlbumDraftPlanningPreview: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case variedAlbum = "Varied"
        case edgeCases = "Edge Cases"
        case layoutLibrary = "Layouts"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .variedAlbum

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            switch tab {
            case .variedAlbum: VariedAlbumTab()
            case .edgeCases: EdgeCasesTab()
            case .layoutLibrary: AlbumLayoutGalleryPreview()
            }
        }
        .navigationTitle("Album Draft Planner")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Varied Album tab

/// docs/specs/SPEC-MODIFY-DRAFT.md § 12 — Regenerate / seed presets / metadata toggle. The
/// Planner itself stays deterministic throughout (§ 2): "Regenerate" only changes the *mock
/// input* fed into it via `AlbumDraftPreviewFactory`, never adds randomness to planning itself.
private struct VariedAlbumTab: View {
    @State private var seed: UInt64 = 1
    @State private var showMetadata = false

    var body: some View {
        VStack(spacing: 0) {
            controls
            AlbumDraftPlanReportView(
                input: AlbumDraftPreviewFactory().makeInput(
                    configuration: AlbumDraftPreviewConfiguration(spreadCount: 9, minimumPhotosPerSpread: 2, maximumPhotosPerSpread: 6, seed: seed)
                ),
                showMetadata: showMetadata
            )
            // A fresh identity per seed forces the whole report (and its `.task`) to restart
            // rather than reusing stale `@State` from the previous seed's plan.
            .id(seed)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                seed &+= 1
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach([1, 2, 3] as [UInt64], id: \.self) { presetSeed in
                    Button("Seed \(presetSeed)") { seed = presetSeed }
                }
            } label: {
                Label("Seed: \(seed)", systemImage: "die.face.3")
            }
            .buttonStyle(.bordered)

            Spacer()

            Toggle("Metadata", isOn: $showMetadata)
                .toggleStyle(.button)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Edge Cases tab

private struct EdgeCasesTab: View {
    private enum Scenario: String, CaseIterable, Identifiable {
        case sixPhotosOneSpread = "6 photos, 1 Spread"
        case thirteenPhotosOneEvent = "13 photos, 1 Event"
        case smallEventsMerge = "Small Events merge"
        var id: String { rawValue }
    }

    @State private var scenario: Scenario = .sixPhotosOneSpread

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scenario", selection: $scenario) {
                ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch scenario {
            case .sixPhotosOneSpread: AlbumDraftPlanReportView(input: Self.sixPhotoInput, showMetadata: true)
            case .thirteenPhotosOneEvent: AlbumDraftPlanReportView(input: Self.thirteenPhotoInput, showMetadata: true)
            case .smallEventsMerge: AlbumDraftPlanReportView(input: Self.smallEventsInput, showMetadata: true)
            }
        }
    }

    // MARK: Case 1 — 6 photos (3 landscape, 2 portrait, 1 square) → 1 Spread, 2 Pages

    private static let sixPhotoInput: AlbumPlanningInput = {
        let event = AlbumPlanningEvent(
            id: "event-1", title: "Weekend Trip", startDate: date(0), endDate: date(2),
            locationName: "Đà Lạt", latitude: nil, longitude: nil,
            selectedPhotos: [
                mockPhoto(id: "p1", eventId: "event-1", orientation: .landscape, hourOffset: 0, isFavorite: true),
                mockPhoto(id: "p2", eventId: "event-1", orientation: .portrait, hourOffset: 1),
                mockPhoto(id: "p3", eventId: "event-1", orientation: .square, hourOffset: 2),
                mockPhoto(id: "p4", eventId: "event-1", orientation: .landscape, hourOffset: 3),
                mockPhoto(id: "p5", eventId: "event-1", orientation: .portrait, hourOffset: 4),
                mockPhoto(id: "p6", eventId: "event-1", orientation: .landscape, hourOffset: 5)
            ]
        )
        return AlbumPlanningInput(albumTitle: nil, events: [event])
    }()

    // MARK: Case 2 — 13 photos in one Event → 3 Spreads, never 6+6+1

    private static let thirteenPhotoInput: AlbumPlanningInput = {
        let photos = (0..<13).map { index in
            mockPhoto(id: "big-\(index)", eventId: "event-big", orientation: [.landscape, .portrait, .square][index % 3], hourOffset: index)
        }
        let event = AlbumPlanningEvent(
            id: "event-big", title: "Big Event", startDate: date(0), endDate: date(13),
            locationName: "Hà Nội", latitude: nil, longitude: nil, selectedPhotos: photos
        )
        return AlbumPlanningInput(albumTitle: nil, events: [event])
    }()

    // MARK: Case 3 — Event A (1 photo), Event B (3 photos), Event C (2 photos)

    private static let smallEventsInput: AlbumPlanningInput = {
        let eventA = AlbumPlanningEvent(
            id: "event-a", title: "Event A", startDate: date(0), endDate: date(0),
            locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [mockPhoto(id: "a1", eventId: "event-a", orientation: .landscape, hourOffset: 0)]
        )
        let eventB = AlbumPlanningEvent(
            id: "event-b", title: "Event B", startDate: date(1), endDate: date(1),
            locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [
                mockPhoto(id: "b1", eventId: "event-b", orientation: .portrait, hourOffset: 24),
                mockPhoto(id: "b2", eventId: "event-b", orientation: .landscape, hourOffset: 25),
                mockPhoto(id: "b3", eventId: "event-b", orientation: .square, hourOffset: 26)
            ]
        )
        let eventC = AlbumPlanningEvent(
            id: "event-c", title: "Event C", startDate: date(2), endDate: date(2),
            locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [
                mockPhoto(id: "c1", eventId: "event-c", orientation: .landscape, hourOffset: 48),
                mockPhoto(id: "c2", eventId: "event-c", orientation: .portrait, hourOffset: 49)
            ]
        )
        return AlbumPlanningInput(albumTitle: nil, events: [eventA, eventB, eventC])
    }()

    private static func date(_ dayOffset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date!)!
    }

    private static func mockPhoto(
        id: String, eventId: String, orientation: PhotoOrientation, hourOffset: Int, isFavorite: Bool = false
    ) -> AlbumPlanningPhoto {
        let (width, height): (Int, Int)
        switch orientation {
        case .landscape: (width, height) = (1600, 1200)
        case .portrait: (width, height) = (1200, 1600)
        case .square: (width, height) = (1400, 1400)
        }
        let creationDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: date(0))
        return AlbumPlanningPhoto(
            id: id, eventId: eventId, creationDate: creationDate, pixelWidth: width, pixelHeight: height,
            coordinate: nil, place: nil, isFavorite: isFavorite, isEdited: false,
            burstIdentifier: nil, originalFilename: nil, exif: nil
        )
    }
}

// MARK: - Shared plan report

/// Runs `AlbumDraftPlanner` against `input` and renders the resulting Draft — cover, per-Spread
/// summary (photo count, orientation, primary place, hero, score), and every Page rendered
/// through the real `AlbumPageRenderer` with distinguishable mock tiles, plus (optionally) the
/// full `AlbumPlanningLog` grouped by stage.
private struct AlbumDraftPlanReportView: View {
    let input: AlbumPlanningInput
    var showMetadata: Bool = false

    @State private var planResult: Result<AlbumPlanningResult, Error>?
    private let layoutRepository: AlbumLayoutRepository = BundleAlbumLayoutRepository()

    private var photosById: [String: AlbumPlanningPhoto] {
        Dictionary(uniqueKeysWithValues: input.events.flatMap(\.selectedPhotos).map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            switch planResult {
            case .none:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await runPlanning() }
            case let .success(result):
                ScrollView {
                    content(result)
                        .padding()
                }
            case let .failure(error):
                Text(String(describing: error))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
    }

    private func runPlanning() async {
        do {
            planResult = .success(try await DefaultAlbumDraftPlanner(layoutRepository: layoutRepository).createDraft(from: input))
        } catch {
            planResult = .failure(error)
        }
    }

    @ViewBuilder
    private func content(_ result: AlbumPlanningResult) -> some View {
        let draft = result.draft
        LazyVStack(alignment: .leading, spacing: 20) {
            summary(draft)
            ForEach(draft.spreads) { spread in
                spreadCard(spread)
            }
            if showMetadata {
                planningLog(result.log)
            }
        }
    }

    private func summary(_ draft: AlbumDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.title).font(.title3.bold())
            if let place = draft.primaryPlace, !place.displayName.isEmpty {
                LabeledContent("Primary place", value: place.displayName)
            }
            LabeledContent("Cover", value: draft.coverPhotoId)
            if let coverImportance = photosById[draft.coverPhotoId]?.importance.totalScore {
                LabeledContent("Cover importance", value: coverImportance.formatted(.number.precision(.fractionLength(1))))
            }
            LabeledContent("Planning version", value: "\(draft.planningVersion ?? 0)")
            LabeledContent("Spreads", value: "\(draft.spreads.count)")
            LabeledContent("Pages", value: "\(draft.numberOfPages)")
            LabeledContent("Total photos", value: "\(draft.totalPhotoCount)")
        }
        .font(.caption)
    }

    private func spreadCard(_ spread: AlbumDraftSpread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spread \(spread.order + 1) — \(spread.photoCount) photos")
                    .font(.subheadline.bold())
                Spacer()
                if let score = spread.planningScore {
                    Text("Score \(score.formatted(.number.precision(.fractionLength(1))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let summary = spread.orientationSummary {
                Text("Landscape \(summary.landscapeCount) · Portrait \(summary.portraitCount) · Square \(summary.squareCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let place = spread.primaryPlace, !place.displayName.isEmpty {
                Text(place.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                pageView(spread.leftPage)
                pageView(spread.rightPage)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func pageView(_ page: AlbumDraftPage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if let layout = try? layoutRepository.layout(id: page.layoutId) {
                    AlbumPageRenderer(
                        layout: layout, assignments: page.assignments,
                        photoProvider: DistinguishableMockPhotoProvider(photosById: photosById)
                    )
                } else {
                    Color(.secondarySystemFill)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("\(page.layoutId) (\(page.assignments.count))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let hero = page.heroPhotoId {
                Text("hero: \(hero)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func planningLog(_ log: AlbumPlanningLog) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planning Log").font(.headline)
            ForEach(AlbumPlanningStage.allCases, id: \.self) { stage in
                let entries = log.entries(in: stage)
                if !entries.isEmpty {
                    DisclosureGroup("\(stage.rawValue.capitalized) (\(entries.count))") {
                        ForEach(entries) { entry in
                            Text("[\(entry.level.rawValue)] \(entry.code): \(entry.message)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(entry.level == .error ? .red : (entry.level == .warning ? .orange : .secondary))
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Album Draft Planner") {
    NavigationStack {
        AlbumDraftPlanningPreview()
    }
}
