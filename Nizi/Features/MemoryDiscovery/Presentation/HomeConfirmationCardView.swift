//
//  HomeConfirmationCardView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI

/// The interactive card from SPRINT-INITIAL-SCAN-MEMORY-JOURNEY-HOME § 12 — presented inline
/// inside the Memory Journey, never a blocking onboarding page. No score/confidence shown (§ 19).
/// Same small, plain-`View`-struct scale as `MemorySelectionEditView` — no ViewModel, no generic
/// card framework (§ 26).
struct HomeConfirmationCardView: View {
    let candidates: [HomeCandidate]
    let onSelect: (HomeCandidate) -> Void
    let onChooseOnMap: () -> Void
    let onSkip: () -> Void

    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("home_confirmation.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("home_confirmation.question")
                    .font(.title3.bold())
            }

            Text("home_confirmation.subtitle")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(candidates) { candidate in
                    candidateRow(candidate)
                }
            }

            Button(action: onChooseOnMap) {
                Text("home_confirmation.action.choose_other")
                    .font(.subheadline.weight(.medium))
            }

            HStack {
                Button("common.action.skip", action: onSkip)
                    .buttonStyle(.bordered)

                Spacer()

                Button {
                    guard let selectedID, let candidate = candidates.first(where: { $0.id == selectedID }) else { return }
                    onSelect(candidate)
                } label: {
                    Text("home_confirmation.action.confirm")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedID == nil)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            selectedID = candidates.first?.id
        }
    }

    private func candidateRow(_ candidate: HomeCandidate) -> some View {
        Button {
            selectedID = candidate.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedID == candidate.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedID == candidate.id ? Color.accentColor : .secondary)
                Text(candidate.displayName ?? coordinateFallback(candidate))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    /// SPEC § 33 — geocoding can fail or lag; a raw coordinate is still a selectable option.
    private func coordinateFallback(_ candidate: HomeCandidate) -> String {
        String(format: "%.3f, %.3f", candidate.centerLatitude, candidate.centerLongitude)
    }
}

#Preview {
    HomeConfirmationCardView(candidates: previewCandidates, onSelect: { _ in }, onChooseOnMap: {}, onSkip: {})
        .padding(.horizontal, 20)
}

private let previewCandidates: [HomeCandidate] = [
    HomeCandidate(id: UUID(), centerLatitude: 21.03, centerLongitude: 105.83, radiusMeters: 400, displayName: "Thanh Xuân, Hà Nội", score: 0.8, distinctYears: 4, distinctMonths: 20),
    HomeCandidate(id: UUID(), centerLatitude: 21.04, centerLongitude: 105.79, radiusMeters: 400, displayName: "Cầu Giấy, Hà Nội", score: 0.6, distinctYears: 2, distinctMonths: 10),
    HomeCandidate(id: UUID(), centerLatitude: 21.05, centerLongitude: 105.88, radiusMeters: 400, displayName: nil, score: 0.5, distinctYears: 2, distinctMonths: 6)
]
