import Foundation

enum EventPlaceResolutionState: String, Equatable {
    case unresolved
    case resolved
    case unavailable
}

struct EventPlace: Equatable {
    let coordinate: PhotoCoordinate
    let subLocality: String?
    let locality: String?
    let subAdministrativeArea: String?
    let administrativeArea: String?
    let country: String?
    let countryCode: String?
    let displayName: String
}
