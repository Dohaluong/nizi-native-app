//
//  PhotoLibraryAuthorizationService.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Isolates PhotoKit's authorization API behind a Domain-owned protocol.
/// See docs/modules/memory-discovery/ARCHITECTURE.md § 6.1.
protocol PhotoLibraryAuthorizationService {
    func currentStatus() async -> PhotoAccessStatus
    func requestAccess() async -> PhotoAccessStatus
    @MainActor func presentLimitedLibraryPicker()
}
