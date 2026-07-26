//
//  AutoEnhancing.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Analyzes one photo and returns suggested `PhotoAdjustments` — never mutates or persists
/// anything itself (PHOTO-EDITOR.md § 20.3, § 14.2: "Trả về các giá trị Adjust đề xuất. Không tự
/// lưu dữ liệu"). Entirely on-device, rule-based — no network call, no generative/ML model.
protocol AutoEnhancing: Sendable {
    func analyze(photoId: String) async throws -> PhotoAdjustments
}

enum AutoEnhanceError: Error, Equatable {
    case assetUnavailable
    case analysisFailed
}
