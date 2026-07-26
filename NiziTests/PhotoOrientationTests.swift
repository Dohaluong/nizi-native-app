//
//  PhotoOrientationTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Testing
@testable import Nizi

struct PhotoOrientationTests {
    @Test func wideImageIsLandscape() {
        #expect(PhotoOrientation.classify(width: 1600, height: 1200) == .landscape)
    }

    @Test func tallImageIsPortrait() {
        #expect(PhotoOrientation.classify(width: 1200, height: 1600) == .portrait)
    }

    @Test func nearSquareImageIsSquare() {
        #expect(PhotoOrientation.classify(width: 1000, height: 1000) == .square)
        #expect(PhotoOrientation.classify(width: 1050, height: 1000) == .square) // ratio 1.05, within tolerance
        #expect(PhotoOrientation.classify(width: 950, height: 1000) == .square) // ratio 0.95, within tolerance
    }

    @Test func justOutsideToleranceIsNotSquare() {
        #expect(PhotoOrientation.classify(width: 1101, height: 1000) == .landscape) // ratio 1.101
        #expect(PhotoOrientation.classify(width: 899, height: 1000) == .portrait) // ratio 0.899
    }

    @Test func zeroWidthReturnsNil() {
        #expect(PhotoOrientation.classify(width: 0, height: 1000) == nil)
    }

    @Test func zeroHeightReturnsNil() {
        #expect(PhotoOrientation.classify(width: 1000, height: 0) == nil)
    }
}
