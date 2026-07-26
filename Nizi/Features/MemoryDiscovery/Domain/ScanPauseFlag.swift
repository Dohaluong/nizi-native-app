//
//  ScanPauseFlag.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Thread-safe pause signal a view can hold and mutate from the main actor while
/// `ScanPhotoLibraryUseCase` polls it in between batches on a background task.
final class ScanPauseFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isPauseRequestedStorage = false

    var isPauseRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPauseRequestedStorage
    }

    func requestPause() {
        lock.lock()
        isPauseRequestedStorage = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        isPauseRequestedStorage = false
        lock.unlock()
    }
}
