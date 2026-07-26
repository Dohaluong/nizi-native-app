//
//  PhotoAccessStatusMappingTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/24/26.
//

import Photos
import Testing
@testable import Nizi

struct PhotoAccessStatusMappingTests {
    @Test func mapsNotDetermined() {
        #expect(PHAuthorizationStatus.notDetermined.toPhotoAccessStatus() == .notDetermined)
    }

    @Test func mapsRestricted() {
        #expect(PHAuthorizationStatus.restricted.toPhotoAccessStatus() == .restricted)
    }

    @Test func mapsDenied() {
        #expect(PHAuthorizationStatus.denied.toPhotoAccessStatus() == .denied)
    }

    @Test func mapsAuthorizedToFull() {
        #expect(PHAuthorizationStatus.authorized.toPhotoAccessStatus() == .full)
    }

    @Test func mapsLimited() {
        #expect(PHAuthorizationStatus.limited.toPhotoAccessStatus() == .limited)
    }
}
