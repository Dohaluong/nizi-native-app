//
//  PhotoAccessStatus.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Photos permission state, mapped from `PHAuthorizationStatus`.
/// See docs/modules/memory-discovery/ARCHITECTURE.md § 6.1.
enum PhotoAccessStatus: Equatable {
    case notDetermined
    case limited
    case full
    case denied
    case restricted
}
