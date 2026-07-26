//
//  AutoEnhanceService.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreImage
import Photos

/// Production `AutoEnhancing` — loads a small analysis-quality image for `photoId`, measures it
/// with `ImageAnalyzer`, and turns that into suggested `PhotoAdjustments` via `AutoEnhanceRules`.
/// Its own small PHAsset/PHImageManager fetch, not a dependency on `PhotoRenderEngine` — same
/// "each Infrastructure class does its own PHAsset lookup" precedent used throughout this module
/// (see docs/modules/PHOTO-EDITOR-IMPLEMENTATION-PLAN.md § 1.1/§ 1.2).
final class AutoEnhanceService: AutoEnhancing, @unchecked Sendable {
    private let imageManager: PHCachingImageManager
    private let ciContext: CIContext

    /// Analysis only needs a small, fast sample — not the preview-quality size the editor's own
    /// live rendering uses, and nowhere near full resolution.
    private static let analysisTargetSize = CGSize(width: 256, height: 256)

    init(imageManager: PHCachingImageManager = PHCachingImageManager(), ciContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.imageManager = imageManager
        self.ciContext = ciContext
    }

    func analyze(photoId: String) async throws -> PhotoAdjustments {
        let cgImage = try await requestAnalysisImage(photoId: photoId)
        let ciImage = CIImage(cgImage: cgImage)
        guard let stats = ImageAnalyzer.analyze(ciImage, using: ciContext) else {
            throw AutoEnhanceError.analysisFailed
        }
        return AutoEnhanceRules.suggestedAdjustments(for: stats)
    }

    private func requestAnalysisImage(photoId: String) async throws -> CGImage {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photoId], options: nil).firstObject else {
            NiziLogger.photoEditor.error("photo_editor_auto_enhance_asset_fetch_failed photoId=\(photoId, privacy: .private)")
            throw AutoEnhanceError.assetUnavailable
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current

        let manager = imageManager
        let requestBox = AutoEnhanceRequestBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestId = manager.requestImage(
                    for: asset, targetSize: Self.analysisTargetSize, contentMode: .aspectFit, options: options
                ) { image, info in
                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    guard let cgImage = image?.cgImage else {
                        continuation.resume(throwing: AutoEnhanceError.assetUnavailable)
                        return
                    }
                    continuation.resume(returning: cgImage)
                }
                requestBox.set(requestId)
            }
        } onCancel: {
            requestBox.cancel(using: manager)
        }
    }
}

private final class AutoEnhanceRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var requestId: PHImageRequestID?

    func set(_ id: PHImageRequestID) {
        lock.lock()
        requestId = id
        lock.unlock()
    }

    func cancel(using manager: PHImageManager) {
        lock.lock()
        let id = requestId
        lock.unlock()
        if let id {
            manager.cancelImageRequest(id)
        }
    }
}
