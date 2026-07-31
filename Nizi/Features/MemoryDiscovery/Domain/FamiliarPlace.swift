//
//  FamiliarPlace.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// A place the user returns to often but that isn't Home — office, school, grandparents' house,
/// a regular café (SPEC § 12). No semantic label is assigned; this only distinguishes
/// familiar-vs-unfamiliar, not what kind of place it is.
struct FamiliarPlace: Identifiable, Equatable {
    let id: UUID
    let clusterID: UUID
    let centerLatitude: Double
    let centerLongitude: Double
    let confidence: Double
}
