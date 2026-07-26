//
//  PhotoKitAuthorizationService.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Photos
import PhotosUI
import UIKit

/// The only place in Memory Discovery allowed to call PhotoKit's authorization API directly.
final class PhotoKitAuthorizationService: PhotoLibraryAuthorizationService {
    func currentStatus() async -> PhotoAccessStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite).toPhotoAccessStatus()
    }

    func requestAccess() async -> PhotoAccessStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status.toPhotoAccessStatus()
    }

    @MainActor
    func presentLimitedLibraryPicker() {
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        else {
            NiziLogger.discovery.error("presentLimitedLibraryPicker failed: no key window root view controller")
            return
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
    }
}

extension PHAuthorizationStatus {
    func toPhotoAccessStatus() -> PhotoAccessStatus {
        switch self {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .full
        case .limited:
            .limited
        @unknown default:
            .denied
        }
    }
}
