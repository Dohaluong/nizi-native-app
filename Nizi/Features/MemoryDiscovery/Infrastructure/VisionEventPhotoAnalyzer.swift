//
//  VisionEventPhotoAnalyzer.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Vision
import UIKit
import Foundation

/// The only place in Photo Curation allowed to call Vision directly. Loads thumbnails through
/// the existing `PhotoAssetProvider` (no new PhotoKit access path), analyzes bounded-concurrently,
/// and clusters near-duplicates in a single forward pass over each session's photos in time order
/// — O(n) per session, not O(n²), by comparing each photo only to the most recently opened
/// cluster. See docs/sprint/SPRINT-005B.md § 9, § 12, § 32.
final class VisionEventPhotoAnalyzer: EventPhotoAnalyzer {
    struct Configuration {
        var thumbnailSize = CGSize(width: 256, height: 256)
        var maxConcurrentAnalyses = 2
        /// Starting point, not tuned against a real library — see docs/sprint/SPRINT-005B.md § 12.
        var nearDuplicateDistanceThreshold: Float = 0.3
        /// Photos taken further apart than this are never clustered as near-duplicates, no
        /// matter how visually similar — a burst of 5–8 shots is normally seconds apart, not
        /// minutes, and treating a 5-minute window as "possibly the same moment" over-merged
        /// distinct shots into one group.
        var nearDuplicateMaxTimeGapSeconds: TimeInterval = 60
        /// A detected document-shaped rectangle below this confidence isn't trusted enough to
        /// call the photo a "document photo" (whiteboard/receipt/paper) — see § 7 of
        /// docs/sprint/SPRINT-005B-TODO.md.
        var documentDetectionMinConfidence: Float = 0.6
        /// The detected rectangle must also cover a large share of the frame — a small rectangle
        /// (e.g. a book spotted in the background of an otherwise normal photo) shouldn't count.
        var documentDetectionMinAreaFraction: Double = 0.5

        static let `default` = Configuration()
    }

    private let assetProvider: PhotoAssetProvider
    private let config: Configuration

    init(assetProvider: PhotoAssetProvider, config: Configuration = .default) {
        self.assetProvider = assetProvider
        self.config = config
    }

    func analyze(
        assets: [IndexedAsset],
        sessions: [PhotoSession],
        onProgress: @escaping (Int, Int) -> Void
    ) async -> [AnalyzedPhoto] {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let orderedSessions = sessions.sorted { $0.startDate < $1.startDate }
        var result: [AnalyzedPhoto] = []

        for (index, session) in orderedSessions.enumerated() {
            let sessionAssets = session.assetIDs
                .compactMap { assetsByID[$0] }
                .sorted { $0.creationDate < $1.creationDate }

            result.append(contentsOf: await analyzeSession(sessionAssets, sessionID: session.id))
            onProgress(index + 1, orderedSessions.count)
        }

        return result
    }

    private func analyzeSession(_ sessionAssets: [IndexedAsset], sessionID: UUID) async -> [AnalyzedPhoto] {
        guard !sessionAssets.isEmpty else { return [] }

        var perAssetResults: [String: (metrics: PhotoQualityMetrics, featurePrint: VNFeaturePrintObservation?, isDocument: Bool)] = [:]

        await withTaskGroup(of: (String, PhotoQualityMetrics, VNFeaturePrintObservation?, Bool).self) { group in
            var nextIndex = 0
            let seedCount = min(config.maxConcurrentAnalyses, sessionAssets.count)

            for _ in 0..<seedCount {
                let asset = sessionAssets[nextIndex]
                group.addTask { await self.analyzeAssetTuple(asset) }
                nextIndex += 1
            }

            while let (assetID, metrics, featurePrint, isDocument) = await group.next() {
                perAssetResults[assetID] = (metrics, featurePrint, isDocument)
                if nextIndex < sessionAssets.count {
                    let asset = sessionAssets[nextIndex]
                    group.addTask { await self.analyzeAssetTuple(asset) }
                    nextIndex += 1
                }
            }
        }

        // Streaming near-duplicate clustering, strictly in chronological order.
        var clusterID: String?
        var clusterRepresentative: VNFeaturePrintObservation?
        var clusterLastSeen: Date?
        var clusterAssignment: [String: String] = [:]

        for asset in sessionAssets {
            guard let entry = perAssetResults[asset.id] else { continue }

            let joinsCurrentCluster: Bool
            if let clusterLastSeen, let clusterRepresentative, let candidate = entry.featurePrint,
               asset.creationDate.timeIntervalSince(clusterLastSeen) <= config.nearDuplicateMaxTimeGapSeconds,
               let featurePrintDistance = try? computeDistance(clusterRepresentative, candidate),
               featurePrintDistance <= config.nearDuplicateDistanceThreshold {
                joinsCurrentCluster = true
            } else {
                joinsCurrentCluster = false
            }

            if joinsCurrentCluster, let clusterID {
                clusterAssignment[asset.id] = clusterID
                clusterLastSeen = asset.creationDate
            } else {
                let newClusterID = asset.id
                clusterID = newClusterID
                clusterRepresentative = entry.featurePrint
                clusterLastSeen = asset.creationDate
                clusterAssignment[asset.id] = newClusterID
            }
        }

        return sessionAssets.compactMap { asset in
            guard let entry = perAssetResults[asset.id] else { return nil }
            return AnalyzedPhoto(
                assetID: asset.id,
                sessionID: sessionID,
                creationDate: asset.creationDate,
                metrics: entry.metrics,
                similarityClusterID: clusterAssignment[asset.id] ?? asset.id,
                isScreenshot: asset.isScreenshot,
                isDocument: entry.isDocument
            )
        }
    }

    private func analyzeAssetTuple(_ asset: IndexedAsset) async -> (String, PhotoQualityMetrics, VNFeaturePrintObservation?, Bool) {
        let (metrics, featurePrint, isDocument) = await analyzeAsset(asset)
        return (asset.id, metrics, featurePrint, isDocument)
    }

    private func analyzeAsset(_ asset: IndexedAsset) async -> (PhotoQualityMetrics, VNFeaturePrintObservation?, Bool) {
        let neutralMetrics = PhotoQualityMetrics(sharpness: 0.5, exposure: 0.5, faceScore: 0.5, isFavorite: asset.isFavorite)

        guard let image = try? await assetProvider.requestThumbnail(
            assetID: asset.id,
            targetSize: config.thumbnailSize,
            networkAccessAllowed: false,
            deliveryMode: .highQuality,
            contentMode: .fill
        ), let cgImage = image.cgImage else {
            // § 31 — asset no longer available; skip gracefully rather than failing the run.
            NiziLogger.discovery.error("curation_asset_thumbnail_unavailable")
            return (neutralMetrics, nil, false)
        }

        let faceRequest = VNDetectFaceLandmarksRequest()
        let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
        let documentRequest = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([faceRequest, featurePrintRequest, documentRequest])
        } catch {
            NiziLogger.discovery.error("curation_vision_request_failed")
        }

        let (sharpness, exposure) = ImagePixelAnalyzer.analyze(cgImage: cgImage)
        let faceScore = Self.faceScore(from: faceRequest.results ?? [])
        let featurePrint = featurePrintRequest.results?.first as? VNFeaturePrintObservation
        let isDocument = Self.isDocument(from: documentRequest.results ?? [], config: config)

        return (
            PhotoQualityMetrics(sharpness: sharpness, exposure: exposure, faceScore: faceScore, isFavorite: asset.isFavorite),
            featurePrint,
            isDocument
        )
    }

    /// A document/whiteboard/receipt-style photo: Vision found a document-shaped rectangle that's
    /// both confidently detected and fills most of the frame (a small rectangle — e.g. a book
    /// visible in the background of an otherwise ordinary photo — doesn't count).
    private static func isDocument(from observations: [VNRectangleObservation], config: Configuration) -> Bool {
        guard let best = observations.max(by: { $0.confidence < $1.confidence }) else { return false }
        guard best.confidence >= config.documentDetectionMinConfidence else { return false }
        let areaFraction = Double(best.boundingBox.width * best.boundingBox.height)
        return areaFraction >= config.documentDetectionMinAreaFraction
    }

    private func computeDistance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) throws -> Float {
        var value: Float = 0
        try a.computeDistance(&value, to: b)
        return value
    }

    // MARK: - Face quality (§ 11.3, § 11.4)

    private static func faceScore(from observations: [VNFaceObservation]) -> Double {
        guard let face = observations.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            // No face isn't a defect for a landscape/object photo — neutral, not penalized.
            return 0.5
        }

        let sizeScore = min(face.boundingBox.width * face.boundingBox.height * 6, 1.0)
        let centerDistance = hypot(face.boundingBox.midX - 0.5, face.boundingBox.midY - 0.5)
        let centeringScore = max(1 - centerDistance * 2, 0)
        let eyeScore = eyeOpennessScore(face: face)

        return 0.4 * sizeScore + 0.2 * centeringScore + 0.4 * eyeScore
    }

    /// Approximate — Vision doesn't expose a direct "eyes closed" signal, so this uses eye
    /// contour aperture (height/width of the landmark region) as a proxy. Deliberately low-weight
    /// and never an absolute disqualifier, per § 11.4 ("Không loại bỏ tuyệt đối ảnh nhắm mắt").
    private static func eyeOpennessScore(face: VNFaceObservation) -> Double {
        guard let landmarks = face.landmarks else { return 0.7 }
        let ratios = [landmarks.leftEye, landmarks.rightEye].compactMap(apertureRatio)
        guard !ratios.isEmpty else { return 0.7 }
        let average = ratios.reduce(0, +) / Double(ratios.count)
        return min(average / 0.25, 1.0)
    }

    private static func apertureRatio(_ region: VNFaceLandmarkRegion2D?) -> Double? {
        guard let region, region.pointCount >= 4 else { return nil }
        let points = region.normalizedPoints
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let width = maxX - minX
        guard width > 0 else { return nil }
        return (maxY - minY) / width
    }
}
