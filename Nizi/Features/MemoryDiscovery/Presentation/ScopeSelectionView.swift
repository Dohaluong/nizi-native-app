//
//  ScopeSelectionView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI

/// Lets the user pick how much of their library to survey before Photos permission is
/// requested. No calendar/date picker by design — see docs/sprint/SPRINT-005-UI.md § 4.
struct ScopeSelectionView: View {
    private enum Mode: Hashable {
        case fullLibrary
        case years
        case months
    }

    let onConfirm: (LibraryScanScope) -> Void

    @State private var mode: Mode = .fullLibrary
    @State private var selectedYears: Set<Int> = []
    @State private var monthPickerYear: Int?
    @State private var selectedMonths: Set<Int> = []

    private let years = LibraryScanScope.selectableYears()

    var body: some View {
        Form {
            Section("scope.title") {
                Picker("scope.picker.range", selection: $mode) {
                    Text("scope.option.full_library").tag(Mode.fullLibrary)
                    Text("scope.option.years").tag(Mode.years)
                    Text("scope.option.months").tag(Mode.months)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            switch mode {
            case .fullLibrary:
                EmptyView()

            case .years:
                Section("scope.section.select_year") {
                    ForEach(years, id: \.self) { year in
                        Toggle(String(year), isOn: binding(for: year))
                    }
                }

            case .months:
                Section("scope.section.year") {
                    Picker("scope.section.year", selection: $monthPickerYear) {
                        Text("scope.picker.year_placeholder").tag(Int?.none)
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(Int?.some(year))
                        }
                    }
                }
                if monthPickerYear != nil {
                    Section("scope.section.select_month") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                            ForEach(1...12, id: \.self) { month in
                                monthChip(month)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Button("common.action.continue") {
                    onConfirm(scope)
                }
                .disabled(!isValid)
            }
        }
        .navigationTitle("scope.title")
    }

    private var scope: LibraryScanScope {
        switch mode {
        case .fullLibrary:
            .fullLibrary
        case .years:
            .years(selectedYears)
        case .months:
            .yearMonths(year: monthPickerYear ?? years.first ?? Calendar.current.component(.year, from: Date()), months: selectedMonths)
        }
    }

    private var isValid: Bool {
        switch mode {
        case .fullLibrary:
            true
        case .years:
            !selectedYears.isEmpty
        case .months:
            monthPickerYear != nil && !selectedMonths.isEmpty
        }
    }

    private func binding(for year: Int) -> Binding<Bool> {
        Binding(
            get: { selectedYears.contains(year) },
            set: { isOn in
                if isOn { selectedYears.insert(year) } else { selectedYears.remove(year) }
            }
        )
    }

    private func monthChip(_ month: Int) -> some View {
        let isSelected = selectedMonths.contains(month)
        return Button {
            if isSelected {
                selectedMonths.remove(month)
            } else {
                selectedMonths.insert(month)
            }
        } label: {
            Text(String(format: "%02d", month))
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedString("scope.month_chip.accessibility_label", defaultValue: "Tháng \(month)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        ScopeSelectionView(onConfirm: { _ in })
    }
}
