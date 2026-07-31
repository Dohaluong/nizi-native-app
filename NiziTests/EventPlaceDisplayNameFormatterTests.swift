import Foundation
import Testing
@testable import Nizi

struct EventPlaceDisplayNameFormatterTests {
    private let formatter = EventPlaceDisplayNameFormatter()

    @Test func vietnameseWardAndCity() {
        #expect(formatter.displayName(for: place(subLocality: "Mỹ An", locality: "Đà Nẵng", country: "Việt Nam", code: "VN"), homeCountryCode: "VN") == "Mỹ An - Đà Nẵng")
    }

    @Test func vietnameseMissingWardAndDuplicateNames() {
        #expect(formatter.displayName(for: place(locality: "Đà Nẵng", administrativeArea: "Đà Nẵng", country: "Việt Nam", code: "VN"), homeCountryCode: "VN") == "Đà Nẵng")
    }

    @Test func vietnameseUsesProvinceOverDistrict() {
        #expect(formatter.displayName(for: place(subLocality: "Đại Mỗ", locality: "Nam Từ Liêm", administrativeArea: "Hà Nội", country: "Việt Nam", code: "VN"), homeCountryCode: "VN") == "Đại Mỗ - Hà Nội")
    }

    @Test func vietnameseUsesSubAdministrativeAreaWhenProvinceIsThere() {
        #expect(formatter.displayName(for: place(subLocality: "Bãi Cháy", subAdministrativeArea: "Quảng Ninh", country: "Việt Nam", code: "VN"), homeCountryCode: "VN") == "Bãi Cháy - Quảng Ninh")
    }

    @Test func vietnameseUsesLocalityAsWardWhenSubLocalityIsMissing() {
        #expect(formatter.displayName(for: place(locality: "Ba Vì", administrativeArea: "Hà Nội", country: "Việt Nam", code: "VN"), homeCountryCode: "VN") == "Ba Vì - Hà Nội")
    }

    @Test func internationalCityAndCountry() {
        #expect(formatter.displayName(for: place(locality: "Tokyo", country: "Nhật Bản", code: "JP"), homeCountryCode: "VN") == "Tokyo - Nhật Bản")
    }

    @Test func internationalAdministrativeFallback() {
        #expect(formatter.displayName(for: place(administrativeArea: "Kyoto", country: "Nhật Bản", code: "JP"), homeCountryCode: "VN") == "Kyoto - Nhật Bản")
    }

    @Test func noLocationReturnsNil() {
        #expect(formatter.displayName(for: place(), homeCountryCode: "VN") == nil)
    }

    private func place(subLocality: String? = nil, locality: String? = nil, subAdministrativeArea: String? = nil, administrativeArea: String? = nil, country: String? = nil, code: String? = nil) -> PhotoPlace {
        PhotoPlace(
            coordinate: PhotoCoordinate(latitude: 16.0, longitude: 108.0)!, name: nil,
            subLocality: subLocality, locality: locality, subAdministrativeArea: subAdministrativeArea,
            administrativeArea: administrativeArea, country: country, isoCountryCode: code,
            displayName: ""
        )
    }
}
