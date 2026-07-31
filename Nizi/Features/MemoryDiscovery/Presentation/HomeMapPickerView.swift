//
//  HomeMapPickerView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI
import MapKit
import CoreLocation

/// "Chọn địa điểm khác…" fallback when none of the 3 Fast Home Candidates are right (SPEC § 22) —
/// pan/zoom, tap to place a marker, confirm. No address entry, no location search (§ 22 explicitly
/// forbids building one if the infrastructure isn't already there). The first MapKit usage in this
/// codebase — kept entirely inside this Presentation file; `CLLocationCoordinate2D` never leaks
/// into Domain, converted to plain `Double` lat/lon right at the `onConfirm` boundary.
struct HomeMapPickerView: View {
    let onConfirm: (Double, Double) -> Void
    let onCancel: () -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    if let selectedCoordinate {
                        Marker("home_map_picker.marker", coordinate: selectedCoordinate)
                    }
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            if let coordinate = proxy.convert(value.location, from: .local) {
                                selectedCoordinate = coordinate
                            }
                        }
                )
            }
            .navigationTitle("home_map_picker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("home_confirmation.action.confirm") {
                        guard let selectedCoordinate else { return }
                        onConfirm(selectedCoordinate.latitude, selectedCoordinate.longitude)
                    }
                    .disabled(selectedCoordinate == nil)
                }
            }
        }
    }
}

#Preview {
    HomeMapPickerView(onConfirm: { _, _ in }, onCancel: {})
}
