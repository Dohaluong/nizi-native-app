//
//  AlbumDraftPlanner.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Turns a set of already-user-selected Event photos into a complete `AlbumDraft` — cover,
/// metadata, Spreads, Pages, layouts, and slot assignments — ready for the Album Layout Renderer.
/// Never touches SwiftUI or persistence. See docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 21 and
/// docs/specs/SPEC-ALBUM-PLANNER.md § 3, § 7.4 (now `async` and returning `AlbumPlanningResult`
/// — location enrichment is the only genuinely asynchronous stage; everything else stays
/// synchronous CPU work).
protocol AlbumDraftPlanning {
    func createDraft(from input: AlbumPlanningInput) async throws -> AlbumPlanningResult
}

struct DefaultAlbumDraftPlanner: AlbumDraftPlanning {
    private let layoutRepository: AlbumLayoutRepository
    private let coverSelector: AlbumCoverSelecting
    private let photoGrouper: AlbumPhotoGrouping
    private let spreadBuilder: AlbumSpreadBuilding
    private let slotAssigner: AlbumPhotoSlotAssigning
    private let layoutPairSelector: AlbumLayoutPairSelecting
    private let locationEnricher: PhotoLocationEnriching
    private let importanceEvaluator: PhotoImportanceEvaluating

    /// `planningVersion` stamped on every draft this planner produces (§ 8.1) — bump this
    /// whenever the planning algorithm changes meaningfully, so a saved draft can always say
    /// which version of the planner produced it.
    static let planningVersion = 1

    init(
        layoutRepository: AlbumLayoutRepository = BundleAlbumLayoutRepository(),
        coverSelector: AlbumCoverSelecting = DefaultAlbumCoverSelector(),
        photoGrouper: AlbumPhotoGrouping = DefaultAlbumPhotoGrouper(),
        spreadBuilder: AlbumSpreadBuilding = DefaultAlbumSpreadBuilder(),
        slotAssigner: AlbumPhotoSlotAssigning = DefaultAlbumPhotoSlotAssigner(),
        locationEnricher: PhotoLocationEnriching = DefaultPhotoLocationEnricher(resolver: ApplePhotoPlaceResolver()),
        importanceEvaluator: PhotoImportanceEvaluating = DefaultPhotoImportanceEvaluator()
    ) {
        self.layoutRepository = layoutRepository
        self.coverSelector = coverSelector
        self.photoGrouper = photoGrouper
        self.spreadBuilder = spreadBuilder
        self.slotAssigner = slotAssigner
        layoutPairSelector = DefaultAlbumLayoutPairSelector(repository: layoutRepository, slotAssigner: slotAssigner)
        self.locationEnricher = locationEnricher
        self.importanceEvaluator = importanceEvaluator
    }

    func createDraft(from input: AlbumPlanningInput) async throws -> AlbumPlanningResult {
        var log = AlbumPlanningLog()

        // 1. Validate selected photos.
        try AlbumPlanningValidator.validateInput(input)
        let rawPhotos = input.events.flatMap(\.selectedPhotos)
        logInputStage(&log, input: input, photos: rawPhotos)

        // Location enrichment (§ 4.8) — the only `await` in this pipeline.
        let enrichment = await locationEnricher.enrich(photos: rawPhotos)
        log.add(AlbumPlanningLogEntry(
            stage: .location, code: "location_clusters_created",
            message: "Resolved \(enrichment.resolvedPlaces.count) place(s) for this Album.",
            metadata: ["placeCount": "\(enrichment.resolvedPlaces.count)"]
        ))
        for warning in enrichment.warnings { log.add(warning) }

        // Importance evaluation (§ 6) — before cover/grouping/spread/layout stages, all of which
        // read `photo.importance` rather than scoring anything themselves.
        let importanceByPhotoId = importanceEvaluator.evaluate(photos: enrichment.photos)
        let photos = enrichment.photos.map { photo -> AlbumPlanningPhoto in
            var updated = photo
            updated.importance = importanceByPhotoId[photo.id] ?? .zero
            return updated
        }
        for photo in photos {
            log.add(AlbumPlanningLogEntry(
                stage: .importance, level: .info, subjectId: photo.id, code: "importance_evaluated",
                message: "\(photo.id) scored \(formatted(photo.importance.totalScore)).",
                metadata: [
                    "photoId": photo.id,
                    "totalScore": "\(photo.importance.totalScore)",
                    "topReasons": photo.importance.reasons.sorted { $0.score > $1.score }.prefix(3).map(\.code).joined(separator: ",")
                ]
            ))
        }

        // Photos flow back into their Events (now carrying place + importance) before grouping —
        // `AlbumPhotoGrouper`/`AlbumSpreadBuilder` operate on `AlbumPlanningEvent`, not a flat list.
        let photosById = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let enrichedEvents = input.events.map { event in
            AlbumPlanningEvent(
                id: event.id, title: event.title, startDate: event.startDate, endDate: event.endDate,
                locationName: event.locationName, latitude: event.latitude, longitude: event.longitude,
                selectedPhotos: event.selectedPhotos.compactMap { photosById[$0.id] }
            )
        }

        // 3. Select cover.
        let cover = try coverSelector.selectCover(from: photos)
        log.add(AlbumPlanningLogEntry(
            stage: .cover, subjectId: cover.id, code: "cover_selected",
            message: "Selected \(cover.id) as cover (importance \(formatted(cover.importance.totalScore))).",
            metadata: [
                "photoId": cover.id, "score": "\(cover.importance.totalScore)",
                "orientation": cover.orientation?.rawValue ?? "unknown", "resolution": "\(cover.pixelCount)",
                "favorite": "\(cover.isFavorite)", "place": cover.place?.displayName ?? ""
            ]
        ))

        // 4–6. Sort events/photos, group by Event (merging singleton Events), build Spreads.
        let groups = photoGrouper.groupPhotos(from: enrichedEvents)
        logGroupingStage(&log, groups: groups)

        let planningSpreads = spreadBuilder.buildSpreads(from: groups)
        guard !planningSpreads.isEmpty else {
            throw AlbumPlanningError.insufficientPhotos(minimum: 2, actual: photos.count)
        }
        logSpreadStage(&log, spreads: planningSpreads)

        // 7. For each Spread: pick a layout pair + photo split (with variety context carried
        // forward from the previous Spread), then assign photos to slots.
        var draftSpreads: [AlbumDraftSpread] = []
        var context = AlbumLayoutPlanningContext.empty
        for (index, spread) in planningSpreads.enumerated() {
            let selection = try layoutPairSelector.selectLayoutPair(for: spread.photos, format: .square, context: context)

            let leftResult = slotAssigner.assign(photos: selection.leftPhotos, to: selection.leftLayout)
            let rightResult = slotAssigner.assign(photos: selection.rightPhotos, to: selection.rightLayout)

            log.add(AlbumPlanningLogEntry(
                stage: .layoutSelection, subjectId: spread.id, code: "layout_pair_selected",
                message: "Spread \(spread.id): \(selection.leftLayout.id) + \(selection.rightLayout.id), score \(formatted(selection.score)).",
                metadata: [
                    "spreadId": spread.id, "leftLayoutId": selection.leftLayout.id, "rightLayoutId": selection.rightLayout.id,
                    "partition": "\(selection.leftPhotos.count)+\(selection.rightPhotos.count)", "score": "\(selection.score)"
                ]
            ))
            for assignment in leftResult.assignments + rightResult.assignments {
                log.add(AlbumPlanningLogEntry(
                    stage: .assignment, subjectId: assignment.photoId, code: "photo_assigned_to_slot",
                    message: "\(assignment.photoId) → \(assignment.slotId)",
                    metadata: ["photoId": assignment.photoId, "slotId": assignment.slotId]
                ))
            }

            let leftHeroPhotoId = Self.heroPhotoId(layout: selection.leftLayout, assignments: leftResult.assignments)
            let rightHeroPhotoId = Self.heroPhotoId(layout: selection.rightLayout, assignments: rightResult.assignments)

            let leftPage = AlbumDraftPage(
                id: "\(spread.id)-left", order: index * 2, layoutId: selection.leftLayout.id, format: .square,
                assignments: leftResult.assignments, sourceEventIds: spread.sourceEventIds,
                heroPhotoId: leftHeroPhotoId,
                primaryPlace: AlbumPrimaryPlaceResolver.resolve(photos: selection.leftPhotos, heroPhotoId: leftHeroPhotoId),
                layoutScore: selection.score, assignmentScore: leftResult.score
            )
            let rightPage = AlbumDraftPage(
                id: "\(spread.id)-right", order: index * 2 + 1, layoutId: selection.rightLayout.id, format: .square,
                assignments: rightResult.assignments, sourceEventIds: spread.sourceEventIds,
                heroPhotoId: rightHeroPhotoId,
                primaryPlace: AlbumPrimaryPlaceResolver.resolve(photos: selection.rightPhotos, heroPhotoId: rightHeroPhotoId),
                layoutScore: selection.score, assignmentScore: rightResult.score
            )

            let spreadHeroPhotoId = Self.spreadHeroPhotoId(
                leftHeroPhotoId: leftHeroPhotoId, rightHeroPhotoId: rightHeroPhotoId, spreadPhotos: spread.photos
            )

            draftSpreads.append(
                AlbumDraftSpread(
                    id: spread.id, order: index, sourceEventIds: spread.sourceEventIds,
                    leftPage: leftPage, rightPage: rightPage,
                    orientationSummary: AlbumPhotoOrientationSummary(photos: spread.photos),
                    primaryPlace: AlbumPrimaryPlaceResolver.resolve(photos: spread.photos, heroPhotoId: spreadHeroPhotoId),
                    heroPhotoId: spreadHeroPhotoId,
                    planningScore: selection.score
                )
            )

            context = context.advanced(
                leftLayoutId: selection.leftLayout.id, rightLayoutId: selection.rightLayout.id,
                partition: AlbumPagePartition(leftCount: selection.leftPhotos.count, rightCount: selection.rightPhotos.count)
            )
        }

        // 2 (assembled here, after cover/spreads are known so metadata reflects the real result).
        let (startDate, endDate) = Self.dateRange(events: enrichedEvents)
        let mainEvent = Self.mainEvent(events: enrichedEvents)
        let sourceEvents = enrichedEvents.map { event in
            AlbumSourceEvent(
                id: event.id, title: event.title, selectedPhotoCount: event.selectedPhotos.count,
                startDate: event.startDate, endDate: event.endDate,
                place: AlbumPrimaryPlaceResolver.resolve(photos: event.selectedPhotos, heroPhotoId: nil)
            )
        }
        let mainEventPlace = mainEvent.flatMap { event in sourceEvents.first { $0.id == event.id }?.place }

        // 8. Build AlbumDraft.
        var draft = AlbumDraft(
            id: UUID().uuidString,
            title: Self.makeTitle(input: input, events: enrichedEvents),
            subtitle: nil,
            coverPhotoId: cover.id,
            startDate: startDate,
            endDate: endDate,
            primaryLocationName: Self.primaryLocationName(events: enrichedEvents),
            primaryPlace: AlbumPrimaryPlaceResolver.resolveAlbumPlace(photos: photos, coverPhotoId: cover.id, mainEventPlace: mainEventPlace),
            sourceEvents: sourceEvents,
            spreads: draftSpreads,
            createdAt: Date(),
            planningVersion: Self.planningVersion,
            planningLog: nil
        )

        // 9. Validate final draft.
        do {
            try AlbumPlanningValidator.validateDraft(draft, expectedPhotoCount: photos.count, repository: layoutRepository)
            log.add(AlbumPlanningLogEntry(stage: .validation, code: "draft_validation_succeeded", message: "Draft \(draft.id) is valid."))
        } catch {
            log.add(AlbumPlanningLogEntry(
                stage: .validation, level: .error, code: "draft_validation_failed",
                message: "Draft \(draft.id) failed validation: \(error).", metadata: ["error": String(describing: error)]
            ))
            throw error
        }

        // Persisted alongside the draft (not just returned in this call's `AlbumPlanningResult`)
        // so a reloaded draft can still explain itself later in Preview/debug — see "Kết quả
        // mong đợi" at the end of the spec.
        draft.planningLog = log

        // 10. Return.
        return AlbumPlanningResult(draft: draft, log: log)
    }

    // MARK: - Logging helpers

    private func logInputStage(_ log: inout AlbumPlanningLog, input: AlbumPlanningInput, photos: [AlbumPlanningPhoto]) {
        log.add(AlbumPlanningLogEntry(
            stage: .input, code: "selected_photos_received",
            message: "Received \(photos.count) photo(s) across \(input.events.count) event(s).",
            metadata: ["photoCount": "\(photos.count)"]
        ))
        log.add(AlbumPlanningLogEntry(
            stage: .input, code: "events_received", message: "\(input.events.count) event(s).",
            metadata: ["eventCount": "\(input.events.count)"]
        ))
        let missingDates = photos.filter { $0.creationDate == nil }.count
        let missingLocations = photos.filter { $0.coordinate == nil }.count
        log.add(AlbumPlanningLogEntry(stage: .input, code: "missing_dates_count", message: "\(missingDates) photo(s) without a date.", metadata: ["count": "\(missingDates)"]))
        log.add(AlbumPlanningLogEntry(stage: .input, code: "missing_locations_count", message: "\(missingLocations) photo(s) without GPS.", metadata: ["count": "\(missingLocations)"]))
    }

    private func logGroupingStage(_ log: inout AlbumPlanningLog, groups: [AlbumPhotoGroup]) {
        for group in groups where group.eventIds.count > 1 {
            log.add(AlbumPlanningLogEntry(
                stage: .grouping, code: "singleton_event_merged",
                message: "Merged \(group.eventIds.joined(separator: ", ")) into one group.",
                metadata: ["eventIds": group.eventIds.joined(separator: ",")]
            ))
        }
        for group in groups {
            log.add(AlbumPlanningLogEntry(
                stage: .grouping, subjectId: group.id, code: "event_group_created",
                message: "\(group.id): \(group.photos.count) photo(s).",
                metadata: ["groupId": group.id, "photoCount": "\(group.photos.count)"]
            ))
        }
    }

    private func logSpreadStage(_ log: inout AlbumPlanningLog, spreads: [AlbumPlanningSpread]) {
        for spread in spreads {
            log.add(AlbumPlanningLogEntry(
                stage: .spread, subjectId: spread.id, code: "spread_created",
                message: "\(spread.id): \(spread.photos.count) photo(s).",
                metadata: [
                    "photoCount": "\(spread.photos.count)", "sourceEventIds": spread.sourceEventIds.joined(separator: ","),
                    "orientationSummary": Self.describe(AlbumPhotoOrientationSummary(photos: spread.photos))
                ]
            ))
        }
        // A group that produced more than one Spread means it was a "large event" split (§ 13.2)
        // — `AlbumSpreadBuilder` names Spreads `"<groupId>-spread-<n>"`, so grouping by that
        // prefix recovers which Spreads came from the same group without the builder needing to
        // report this itself.
        let byGroup = Dictionary(grouping: spreads) { $0.id.components(separatedBy: "-spread-").first ?? $0.id }
        for (groupId, groupSpreads) in byGroup where groupSpreads.count > 1 {
            log.add(AlbumPlanningLogEntry(
                stage: .spread, code: "large_event_split",
                message: "\(groupId) split into \(groupSpreads.count) spreads.",
                metadata: ["groupId": groupId, "spreadCount": "\(groupSpreads.count)"]
            ))
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func describe(_ summary: AlbumPhotoOrientationSummary) -> String {
        "landscape=\(summary.landscapeCount),portrait=\(summary.portraitCount),square=\(summary.squareCount)"
    }

    // MARK: - § 8.3 Spread hero

    /// The photo assigned to a layout's `hero` slot, if that layout has one.
    private static func heroPhotoId(layout: AlbumPageLayout, assignments: [AlbumPhotoAssignment]) -> String? {
        guard let heroSlotId = layout.slots.first(where: { $0.role == .hero })?.id else { return nil }
        return assignments.first { $0.slotId == heroSlotId }?.photoId
    }

    /// § 8.3 — whichever page hero has higher importance; if neither page has a hero slot, the
    /// single most important photo in the Spread.
    private static func spreadHeroPhotoId(leftHeroPhotoId: String?, rightHeroPhotoId: String?, spreadPhotos: [AlbumPlanningPhoto]) -> String? {
        let photosById = Dictionary(uniqueKeysWithValues: spreadPhotos.map { ($0.id, $0) })
        let pageHeroes = [leftHeroPhotoId, rightHeroPhotoId].compactMap { $0 }
        if !pageHeroes.isEmpty {
            return pageHeroes.max { (photosById[$0]?.importance.totalScore ?? 0) < (photosById[$1]?.importance.totalScore ?? 0) }
        }
        return spreadPhotos.max { $0.importance.totalScore < $1.importance.totalScore }?.id
    }

    // MARK: - § 10 Metadata

    private static func mainEvent(events: [AlbumPlanningEvent]) -> AlbumPlanningEvent? {
        events.max { lhs, rhs in
            if lhs.selectedPhotos.count != rhs.selectedPhotos.count {
                return lhs.selectedPhotos.count < rhs.selectedPhotos.count
            }
            return lhs.id > rhs.id // tie-break: lexically-first ID wins under `max`
        }
    }

    /// § 10.1 — user title → single-Event title → common location → Event month/year → fallback.
    private static func makeTitle(input: AlbumPlanningInput, events: [AlbumPlanningEvent]) -> String {
        if let albumTitle = input.albumTitle, !albumTitle.isEmpty {
            return albumTitle
        }
        if events.count == 1, let eventTitle = events[0].title, !eventTitle.isEmpty {
            return eventTitle
        }
        if let location = primaryLocationName(events: events) {
            return location
        }
        if let start = dateRange(events: events).start {
            return start.formatted(.dateTime.month(.wide).year())
        }
        return localizedString("album.creation.default_title", defaultValue: "New Album")
    }

    /// § 10.2 — Event dates take priority; photo creation dates are only a fallback for Events
    /// that have none.
    private static func dateRange(events: [AlbumPlanningEvent]) -> (start: Date?, end: Date?) {
        let eventStarts = events.compactMap(\.startDate)
        let eventEnds = events.compactMap(\.endDate)
        if let start = eventStarts.min() {
            let end = eventEnds.max() ?? eventStarts.max()
            return (start, end)
        }
        let photoDates = events.flatMap(\.selectedPhotos).compactMap(\.creationDate)
        return (photoDates.min(), photoDates.max())
    }

    /// § 10.3 — single Event uses its location directly; multiple Events use whichever
    /// non-empty location name recurs most often (lexical tie break), never a concatenation.
    private static func primaryLocationName(events: [AlbumPlanningEvent]) -> String? {
        if events.count == 1 { return events[0].locationName }
        let locations = events.compactMap(\.locationName).filter { !$0.isEmpty }
        guard !locations.isEmpty else { return nil }
        let counts = Dictionary(grouping: locations, by: { $0 }).mapValues(\.count)
        let maxCount = counts.values.max() ?? 0
        return counts.filter { $0.value == maxCount }.keys.sorted().first
    }
}
