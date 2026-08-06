//
//  ScanCheckpointRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

protocol ScanCheckpointRepository {
    func checkpoint(for scanType: ScanType) async throws -> ScanCheckpoint?
    func checkpoint(
        for scanType: ScanType, scopeKey: String, libraryVersion: String, algorithmVersion: Int
    ) async throws -> ScanCheckpoint?
    func save(_ checkpoint: ScanCheckpoint) async throws
    func clear(_ scanType: ScanType) async throws
}
