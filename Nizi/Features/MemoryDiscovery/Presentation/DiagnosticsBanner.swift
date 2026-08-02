//
//  DiagnosticsBanner.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI

/// Shared clarity banner for debug-only Diagnostics screens (SPRINT-NEXT § 24) — makes it
/// unambiguous whether a given screen's "Run" recomputes something purely for display, or
/// actually exercises/persists via the real production pipeline.
struct DiagnosticsBanner: View {
    enum Tone {
        case previewOnly
        case production
        case neutral
    }

    let title: String
    let subtitle: String
    var tone: Tone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold())
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        .listRowInsets(EdgeInsets())
        .padding(.vertical, 2)
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral: Color.secondary.opacity(0.1)
        case .production: Color.orange.opacity(0.15)
        case .previewOnly: Color.blue.opacity(0.12)
        }
    }
}
